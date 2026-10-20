import Foundation

enum AppConfig {
    /// A non-routable placeholder for model construction; onboarding prevents automatic requests.
    static let defaultBaseURL = URL(string: "https://unconfigured.invalid")!
    static var profile: ConnectionProfile? { try? CredentialStore.shared.load() }
    static var isConfigured: Bool { profile != nil }
    static var baseURL: URL { profile?.serverURL ?? defaultBaseURL }

    static func validatedServerURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }

    static var webSocketURL: URL { webSocketURL(for: baseURL) }
    static func webSocketURL(for server: URL) -> URL {
        let endpoint = server.appending(path: "api/remote.mux")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.scheme = server.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    static func accessHeaders(for server: URL) -> [String: String] { profile?.headers(for: server) ?? [:] }
}
