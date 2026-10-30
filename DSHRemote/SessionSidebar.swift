import SwiftUI

struct SessionSidebar: View {
    let sessions: [SessionSummary]
    let workspaces: [DesktopWorkspace]?
    let archivedCount: Int
    let currentSessionID: String?
    let loading: Bool
    let conversationsSelected: Bool
    let workspacesSelected: Bool
    let archivedSelected: Bool
    let updatingSessionID: String?
    let actionsEnabled: Bool
    let onClose: () -> Void
    let onConversations: () -> Void
    let onWorkspaces: () -> Void
    let onWorkspace: (DesktopWorkspace) -> Void
    let onArchived: () -> Void
    let onSettings: () -> Void
    let onNew: () -> Void
    let onSelect: (String) -> Void
    let onArchive: (SessionSummary) -> Void
    @State private var expandedWorkspaceIDs: Set<String> = []
    @ScaledMetric(relativeTo: .body) private var iconWidth = 25.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var groups: [SessionGroup] { SessionGroup.make(sessions: sessions, workspaces: workspaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("dsh link").font(.system(.title, design: .serif)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                Button("收起侧栏", systemImage: "chevron.left") { onClose() }
                    .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
            }
            .padding(.leading, 24).padding(.trailing, 12).padding(.top, 18).padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    navigationRow("对话", icon: "bubble.left.and.bubble.right", selected: conversationsSelected) {
                        onConversations()
                    }
                    navigationRow("工作区", icon: "folder", selected: workspacesSelected) { onWorkspaces() }
                    navigationRow("已归档", icon: "archivebox", selected: archivedSelected, badge: archivedCount) { onArchived() }
                    Text("工作区分组").font(.subheadline).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 16).padding(.top, 29).padding(.bottom, 10)
                    if sessions.isEmpty {
                        Text(loading ? "正在同步对话…" : "你的对话会显示在这里")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16).padding(.vertical, 18)
                    }
                    ForEach(groups) { group in
                        workspaceGroup(group)
                    }
                    Button {
                        onConversations()
                    } label: {
                        HStack(spacing: 6) {
                            Text("所有对话")
                            Image(systemName: "chevron.right").font(.caption)
                        }.font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(minHeight: 48).padding(.horizontal, 16)
                    }.buttonStyle(NavigationRowButtonStyle()).padding(.top, 6)
                }.padding(.horizontal, 12)
            }
            footerLayout {
                Button { onSettings() } label: {
                    Image(systemName: "slider.horizontal.3").font(.body).foregroundStyle(Theme.text)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: 46, height: 46)
                        .background(Theme.bg, in: .circle)
                        .overlay { Circle().strokeBorder(Theme.stroke, lineWidth: 0.75) }
                }.buttonStyle(NavigationRowButtonStyle()).accessibilityLabel("设置")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button(action: onNew) {
                    Label("新建对话", systemImage: "plus").font(.subheadline.weight(.medium))
                        .padding(.horizontal, 17).frame(minHeight: 46)
                        .foregroundStyle(Theme.onAccent).background(Theme.accent, in: .capsule)
                }.buttonStyle(NavigationRowButtonStyle())
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 12)
        }
        .onChange(of: groups.map(\.id), initial: true) { _, _ in
            guard expandedWorkspaceIDs.isEmpty, let group = groups.first(where: { $0.sessions.contains { $0.id == currentSessionID } }) ?? groups.first else { return }
            expandedWorkspaceIDs.insert(group.id)
        }
        .onChange(of: currentSessionID) { _, id in
            if let group = groups.first(where: { $0.sessions.contains { $0.id == id } }) { expandedWorkspaceIDs.insert(group.id) }
        }
    }

    private func workspaceGroup(_ group: SessionGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expandedWorkspaceIDs.contains(group.id) { expandedWorkspaceIDs.remove(group.id) }
                else { expandedWorkspaceIDs.insert(group.id) }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: expandedWorkspaceIDs.contains(group.id) ? "chevron.down" : "chevron.right").font(.caption)
                    Image(systemName: "folder").font(.subheadline)
                    Text(group.title).font(.subheadline).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(group.sessions.count)").font(.caption).monospacedDigit()
                }.foregroundStyle(Theme.muted).padding(.horizontal, 16).frame(minHeight: 48).contentShape(.rect)
            }.buttonStyle(NavigationRowButtonStyle())
                .accessibilityLabel("\(group.title)，\(group.sessions.count) 个对话，\(expandedWorkspaceIDs.contains(group.id) ? "已展开" : "已收起")")
            if expandedWorkspaceIDs.contains(group.id) {
                ForEach(group.sessions.prefix(5)) { session in
                    SessionActionRow(session: session, compact: true, selected: currentSessionID == session.id,
                                     updating: updatingSessionID == session.id, actionsEnabled: actionsEnabled,
                                     onSelect: { onSelect(session.id) }, onArchive: { onArchive(session) })
                }.padding(.leading, 12)
                if group.sessions.count > 5 {
                    Button("查看全部 \(group.sessions.count) 个对话") {
                        if let workspace = group.workspace { onWorkspace(workspace) }
                        else { onConversations() }
                    }.font(.footnote).foregroundStyle(Theme.muted).frame(minHeight: 44).padding(.leading, 32)
                }
            }
        }
    }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func navigationRow(_ title: String, icon: String, selected: Bool, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: iconWidth)
                Text(title).font(.body)
                Spacer()
                if badge > 0 { Text("\(badge)").font(.caption).foregroundStyle(Theme.muted).monospacedDigit() }
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 16).padding(.vertical, 16)
            .background(selected ? Theme.raised.opacity(0.8) : .clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }.buttonStyle(NavigationRowButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

}
