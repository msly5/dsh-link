import Foundation

/// The QR contains credentials. Never log the link or persist it outside Keychain.
struct PairingInvitation: Equatable {
    let profile: ConnectionProfile
    let expiresAt: Date

    private struct Payload: Decodable {
        let version: Int
        let expires_at: Double
        let server_url: String
        let client_id: String
        let client_secret: String
    }

    init(scannedValue: String, now: Date = .now) throws {
        guard scannedValue.utf8.count <= 2_000,
              let url = URLComponents(string: scannedValue),
              url.scheme?.lowercased() == "dshremote", url.host?.lowercased() == "configure",
              url.path.isEmpty, url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let items = url.queryItems, items.count == 1, items[0].name == "data",
              let encoded = items[0].value, !encoded.isEmpty,
              encoded.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw RemoteError(message: "这不是有效的 dsh link 配置二维码。")
        }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.version == 1,
              payload.expires_at.isFinite else {
            throw RemoteError(message: "配置二维码格式不受支持，请在 Mac 上重新生成。")
        }
        let expiry = Date(timeIntervalSince1970: payload.expires_at)
        guard expiry > now, expiry.timeIntervalSince(now) <= 360 else {
            throw RemoteError(message: "二维码已过期或设备时间不一致，请在 Mac 上重新生成。")
        }
        profile = try ConnectionProfile(server: payload.server_url, clientID: payload.client_id, clientSecret: payload.client_secret)
        expiresAt = expiry
    }
}
