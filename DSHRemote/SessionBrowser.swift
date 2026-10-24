import SwiftUI

struct SessionBrowser: View {
    let sessions: [SessionSummary]
    let filtered: [SessionSummary]
    let workspaces: [DesktopWorkspace]?
    let loading: Bool
    let errorText: String?
    let workspaceError: String?
    let archived: Bool
    let updatingSessionID: String?
    let actionsEnabled: Bool
    @Binding var query: String
    let onRefresh: () async -> Void
    let onSelect: (String) -> Void
    let onArchive: (SessionSummary) -> Void
    @State private var groupByWorkspace = true

    private var groups: [SessionGroup] {
        if groupByWorkspace { return SessionGroup.make(sessions: filtered, workspaces: workspaces) }
        let calendar = Calendar.current
        let today = filtered.filter { $0.updatedAtDate.map { calendar.isDateInToday($0) } ?? false }
        let yesterday = filtered.filter { $0.updatedAtDate.map { calendar.isDateInYesterday($0) } ?? false }
        let earlier = filtered.filter { session in
            guard let date = session.updatedAtDate else { return true }
            return !calendar.isDateInToday(date) && !calendar.isDateInYesterday(date)
        }
        return [("今天", today), ("昨天", yesterday), ("更早", earlier)].filter { !$0.1.isEmpty }
            .map { SessionGroup(id: $0.0, title: $0.0, workspace: nil, sessions: $0.1) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                searchField
                HStack {
                    Text(archived ? "已归档的对话" : "全部对话").font(.subheadline).foregroundStyle(Theme.muted)
                    Spacer()
                    Picker("分组方式", selection: $groupByWorkspace) {
                        Text("按工作区").tag(true)
                        Text("按时间").tag(false)
                    }.pickerStyle(.menu).font(.subheadline)
                }.padding(.horizontal, 14)
                if let workspaceError {
                    Label("工作区同步失败。\(workspaceError)", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(Theme.warning).padding(.horizontal, 14)
                }
                if let errorText, !sessions.isEmpty {
                    Label(errorText, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(Theme.warning).padding(.horizontal, 14)
                }
                if loading && sessions.isEmpty {
                    ProgressView("正在同步…").font(.subheadline).padding(.vertical, 40)
                } else if let errorText, sessions.isEmpty {
                    VStack(spacing: 20) {
                        EmptyState(icon: "wifi.exclamationmark", title: "暂时无法连接", detail: errorText)
                        Button("重新连接") { Task { await onRefresh() } }.font(.subheadline).frame(minHeight: 44)
                    }.padding(.top, 50)
                } else if filtered.isEmpty {
                    EmptyState(icon: archived ? "archivebox" : "bubble.left", title: query.isEmpty ? (archived ? "还没有归档会话" : "还没有对话") : "没有找到对话",
                               detail: query.isEmpty ? (archived ? "归档后的会话会保存在这里，可以随时恢复。" : "新建一个对话，开始下一段工作。") : "试试其他名称或目录关键词。")
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 7) {
                                if groupByWorkspace { Image(systemName: "folder") }
                                Text(group.title)
                                Text("\(group.sessions.count)").monospacedDigit()
                            }.font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 14).padding(.bottom, 5)
                            ForEach(group.sessions) { session in
                                SessionActionRow(session: session, desktopGroup: groupByWorkspace ? nil : workspaces?.first { $0.sessionIds.contains(session.id) }?.displayName,
                                                 archived: archived, updating: updatingSessionID == session.id, actionsEnabled: actionsEnabled,
                                                 onSelect: { onSelect(session.id) }, onArchive: { onArchive(session) })
                            }
                        }
                    }
                }
            }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 20)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).refreshable { await onRefresh() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("搜索对话", text: $query).font(.body).foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
            if !query.isEmpty {
                Button("清空搜索", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
            }
        }.padding(.horizontal, 15).frame(minHeight: 46)
            .background(Theme.code, in: .capsule).padding(.horizontal, 10).padding(.bottom, 12)
    }

}
