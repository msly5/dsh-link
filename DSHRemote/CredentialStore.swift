import Foundation
import Security

/// One atomic Keychain item binds credentials to their exact server URL. No iCloud sync or backups.
struct CredentialStore {
    static let shared = CredentialStore()
    let service: String
    init(service: String = "app.dshremote.connection.v1") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
    }

    func load() throws -> ConnectionProfile? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        // Decoding revalidates both current and legacy profiles.
        return try JSONDecoder().decode(ConnectionProfile.self, from: data)
    }

    func save(_ profile: ConnectionProfile) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(profile),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            values.forEach { item[$0.key] = $0.value }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private func failure(_ status: OSStatus) -> RemoteError {
        if status == errSecMissingEntitlement {
            return RemoteError(message: "此构建缺少钥匙串签名权限，请使用 Xcode 签名后安装。")
        }
        return RemoteError(message: "无法访问系统钥匙串（\(status)），请解锁设备后重试。")
    }
}
