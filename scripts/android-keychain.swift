// macOS-only signing storage. Called by sign-android.py over captured pipes.
import Foundation
import Security
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: "dsh-link.android-release",
                           kSecAttrAccount as String: "release-signing-v1"]
func fail() -> Never { FileHandle.standardError.write(Data("Android signing Keychain operation failed.\n".utf8)); exit(1) }
if CommandLine.arguments.dropFirst().first == "create" {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { fail() }
    var record = query
    record[kSecValueData as String] = data
    record[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(record as CFDictionary, nil) == errSecSuccess else { fail() }
} else {
    var search = query
    search[kSecReturnData as String] = true
    search[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(search as CFDictionary, &result)
    if status == errSecItemNotFound { exit(3) }
    guard status == errSecSuccess, let data = result as? Data else { fail() }
    FileHandle.standardOutput.write(data)
}
