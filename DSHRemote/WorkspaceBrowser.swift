import SwiftUI

struct WorkspaceBrowser: View {
    let workspaces: [DesktopWorkspace]?
    let archivedSessionIDs: Set<String>
    let errorText: String?
    let onRefresh: () async -> Void
    let onSelect: (DesktopWorkspace) -> Void

    @ScaledMetric(relativeTo: .body) private var iconWidth = 25.0
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text("与桌面端保持同步").font(.subheadline).foregroundStyle(Theme.muted).padding(.horizontal, 14).padding(.bottom, 22)
                if let workspaces, !workspaces.isEmpty {
                    ForEach(workspaces) { workspace in
                        Button {
                            onSelect(workspace)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder").font(.title3).foregroundStyle(Theme.muted).frame(width: iconWidth)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(workspace.displayName).font(.body).foregroundStyle(Theme.text)
                                    Text("\(workspace.sessionIds.filter { !archivedSessionIDs.contains($0) }.count) 个对话").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }.padding(16).frame(minHeight: 72).contentShape(.rect)
                        }.buttonStyle(NavigationRowButtonStyle())
                    }
                } else if let errorText {
                    EmptyState(icon: "wifi.exclamationmark", title: "工作区暂未同步", detail: errorText)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                    Button("重新同步") { Task { await onRefresh() } }.frame(maxWidth: .infinity, minHeight: 44)
                } else if workspaces == nil {
                    ProgressView("正在同步工作区…").frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    EmptyState(icon: "folder", title: "还没有工作区", detail: "连接 Mac 后，你的桌面工作区会显示在这里。")
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }.padding(.horizontal, 12).padding(.top, 20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.refreshable { await onRefresh() }
    }

}
