import Foundation

struct ConnectionProfile: Codable, Equatable {
    let serverURL: URL
    let clientID: String
    let clientSecret: String

    init(server: String, clientID: String, clientSecret: String) throws {
        guard let url = AppConfig.validatedServerURL(server), url.scheme == "https" else {
            throw RemoteError(message: "请输入有效的 HTTPS 服务器地址。")
        }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty, !id.contains(where: \.isWhitespace),
              !secret.contains(where: \.isWhitespace),
              id.utf8.allSatisfy({ (33...126).contains($0) }), secret.utf8.allSatisfy({ (33...126).contains($0) }),
              id.utf8.count <= 4096, secret.utf8.count <= 4096 else {
            throw RemoteError(message: "请填写 Cloudflare Service Token 的 Client ID 和 Client Secret，不能包含空白字符。")
        }
        serverURL = url
        self.clientID = id
        self.clientSecret = secret
    }

    func headers(for server: URL) -> [String: String] {
        guard AppConfig.validatedServerURL(server.absoluteString) == serverURL else { return [:] }
        return ["CF-Access-Client-Id": clientID, "CF-Access-Client-Secret": clientSecret]
    }
}
