import XCTest
@testable import DSHRemoteCore

final class SessionGroupTests: XCTestCase {
    private func session(_ id: String, cwd: String? = "/same") -> SessionSummary {
        SessionSummary(sessionId: id, updatedAt: nil, running: false, blank: false, cwd: cwd, projections: nil)
    }

    func testGroupingUsesRegistryMembershipAndOrderRatherThanDirectoryNames() {
        let workspaces = [
            DesktopWorkspace(workspaceId: "second", path: "/same", title: "Second", sessionIds: ["b"]),
            DesktopWorkspace(workspaceId: "first", path: "/same", title: "First", sessionIds: ["a", "c"]),
            DesktopWorkspace(workspaceId: "empty", path: "/empty", title: "Empty", sessionIds: [])
        ]
        let groups = SessionGroup.make(sessions: [session("c"), session("a"), session("b"), session("orphan")], workspaces: workspaces)
        XCTAssertEqual(groups.map(\.id), ["second", "first", "ungrouped"])
        XCTAssertEqual(groups[1].sessions.map(\.id), ["c", "a"])
        XCTAssertEqual(groups[2].sessions.map(\.id), ["orphan"])
    }

    func testFilteredAndRestoredSessionsRetainTheirOriginalWorkspace() {
        let workspace = DesktopWorkspace(workspaceId: "project", path: "/same", title: "Project", sessionIds: ["active", "archived"])
        let all = [session("active"), session("archived")]
        let archived = Set(["archived"])
        let groups = SessionGroup.make(sessions: all.filter { !archived.contains($0.id) }, workspaces: [workspace])
        XCTAssertEqual(groups.first?.sessions.map(\.id), ["active"])
        let restored = SessionGroup.make(sessions: all, workspaces: [workspace])
        XCTAssertEqual(restored.first?.sessions.map(\.id), ["active", "archived"])
        let archiveGroups = SessionGroup.make(sessions: all.filter { archived.contains($0.id) }, workspaces: [workspace])
        XCTAssertEqual(archiveGroups.first?.id, "project")
    }

    func testDirectoryFallbackOnlyWhenWorkspaceDirectoryIsUnavailable() {
        let items = [session("a", cwd: "/first"), session("b", cwd: "/other/first"), session("c", cwd: nil)]
        let fallback = SessionGroup.make(sessions: items, workspaces: nil)
        XCTAssertEqual(fallback.map(\.id), ["directory:/first", "directory:/other/first", "directory:"])
        XCTAssertEqual(fallback.map(\.title), ["first", "first", "未分组"])
        XCTAssertEqual(SessionGroup.make(sessions: items, workspaces: []).map(\.id), ["ungrouped"])
    }
}
