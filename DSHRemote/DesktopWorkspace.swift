import Foundation

struct DesktopWorkspace: Codable, Identifiable, Equatable, Sendable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]

    var id: String { workspaceId }
    var displayName: String {
        title == "default-workspace" && path.hasSuffix("/deepseek-harness/default-workspace") ? "默认工作区" : title
    }
}
