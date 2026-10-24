import Foundation

struct SessionGroup: Identifiable {
    let id: String
    let title: String
    let workspace: DesktopWorkspace?
    let sessions: [SessionSummary]

    /// Registry membership is authoritative; equal directories do not imply membership.
    static func make(sessions: [SessionSummary], workspaces: [DesktopWorkspace]?) -> [SessionGroup] {
        var remaining = sessions
        var groups: [SessionGroup] = []
        if let workspaces {
            for workspace in workspaces {
                let ids = Set(workspace.sessionIds)
                let members = remaining.filter { ids.contains($0.id) }
                remaining.removeAll { ids.contains($0.id) }
                if !members.isEmpty {
                    groups.append(SessionGroup(id: workspace.id, title: workspace.displayName,
                                               workspace: workspace, sessions: members))
                }
            }
            if !remaining.isEmpty {
                groups.append(SessionGroup(id: "ungrouped", title: "未分组", workspace: nil, sessions: remaining))
            }
        } else {
            // Keep conversations usable if the optional workspace directory is unavailable.
            var paths: [String] = []
            var byPath: [String: [SessionSummary]] = [:]
            for session in sessions {
                let path = session.cwd ?? ""
                if byPath[path] == nil { paths.append(path) }
                byPath[path, default: []].append(session)
            }
            groups = paths.map { path in
                SessionGroup(id: "directory:" + path, title: path.isEmpty ? "未分组" : (path as NSString).lastPathComponent,
                             workspace: nil, sessions: byPath[path] ?? [])
            }
        }
        return groups
    }
}
