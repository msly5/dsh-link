import Foundation

struct ConnectionProfile: Codable, Equatable {
    enum AuthMode: String, Codable { case access, quickTunnel = "quick_tunnel" }

    let serverURL: URL
    let authMode: AuthMode
    let clientID: String
    let clientSecret: String
    let connectionKey: String

    init(server: String, clientID: String = "", clientSecret: String = "", authMode: AuthMode = .access, connectionKey: String = "") throws {
        guard let url = AppConfig.validatedServerURL(server), url.scheme == "https" else {
            throw RemoteError(message: "请输入有效的 HTTPS 服务器地址。")
        }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = connectionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if authMode == .quickTunnel {
            guard key.utf8.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw RemoteError(message: "请填写 Mac 连接窗口中的 64 位连接密钥，或重新扫码。")
            }
        } else {
            guard !id.isEmpty, !secret.isEmpty, !id.contains(where: \.isWhitespace), !secret.contains(where: \.isWhitespace),
                  id.utf8.allSatisfy({ (33...126).contains($0) }), secret.utf8.allSatisfy({ (33...126).contains($0) }),
                  id.utf8.count <= 4096, secret.utf8.count <= 4096 else {
                throw RemoteError(message: "请填写 Cloudflare Service Token 的 Client ID 和 Client Secret，不能包含空白字符。")
            }
        }
        serverURL = url
        self.authMode = authMode
        self.clientID = authMode == .access ? id : ""
        self.clientSecret = authMode == .access ? secret : ""
        self.connectionKey = authMode == .quickTunnel ? key : ""
    }

    private enum CodingKeys: String, CodingKey { case serverURL, authMode, clientID, clientSecret, connectionKey }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(server: values.decode(URL.self, forKey: .serverURL).absoluteString,
                      clientID: values.decodeIfPresent(String.self, forKey: .clientID) ?? "",
                      clientSecret: values.decodeIfPresent(String.self, forKey: .clientSecret) ?? "",
                      authMode: values.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .access,
                      connectionKey: values.decodeIfPresent(String.self, forKey: .connectionKey) ?? "")
    }

    func headers(for server: URL) -> [String: String] {
        guard AppConfig.validatedServerURL(server.absoluteString) == serverURL else { return [:] }
        if authMode == .quickTunnel { return ["Authorization": "Bearer " + connectionKey] }
        return ["CF-Access-Client-Id": clientID, "CF-Access-Client-Secret": clientSecret]
    }
}
