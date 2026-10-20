import Foundation

struct WorkspaceSnapshot: Decodable, Sendable {
    let items: [DesktopWorkspace]
    let archivedSessionIds: [String]

    func preferredWorkspace(sessionId: String?, savedId: String?) -> DesktopWorkspace? {
        if let sessionId, let current = items.first(where: { $0.sessionIds.contains(sessionId) }) { return current }
        return items.first(where: { $0.id == savedId }) ?? items.first
    }

    static func decodeFrame(_ data: Data) throws -> WorkspaceSnapshot? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteError(message: "工作区响应格式异常")
        }
        if root["type"] as? String == "error" {
            let error = root["error"] as? [String: Any]
            throw RemoteError(message: error?["message"] as? String ?? "无法读取桌面工作区")
        }
        let frame = root["value"] as? [String: Any] ?? root
        guard frame["type"] as? String == "baseline" || frame["type"] as? String == "replace" else { return nil }
        guard let value = frame["value"] as? [String: Any] else { throw RemoteError(message: "工作区响应缺少列表") }
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
