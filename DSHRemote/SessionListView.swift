import SwiftUI

struct SessionListView: View {
    @State private var sessions: [SessionSummary] = []
    @State private var workspaces: [DesktopWorkspace]?
    @State private var workspaceLoadID = UUID()
    @State private var path: [SessionSummary] = []
    @State private var pendingSessionId: String?
    @State private var loading = false
    @State private var errorText: String?
    @State private var showSettings = !AppConfig.isConfigured
    @State private var query = ""
    @State private var showNewSession = false
    @State private var initialLoadFinished = false
    @State private var loadID = UUID()
    @Environment(\.scenePhase) private var scenePhase

    private var lastSessionKey: String { "lastSessionId." + AppConfig.baseURL.absoluteString }

    private var filtered: [SessionSummary] {
        guard !query.isEmpty else { return sessions }
        return sessions.filter {
            $0.title.localizedStandardContains(query) || ($0.cwd ?? "").localizedStandardContains(query)
        }
    }

    private var groups: [(String, [SessionSummary])] {
        var today: [SessionSummary] = []
        var yesterday: [SessionSummary] = []
        var earlier: [SessionSummary] = []
        let cal = Calendar.current
        for session in filtered {
            guard let date = session.updatedAtDate else {
                earlier.append(session)
                continue
            }
            if cal.isDateInToday(date) { today.append(session) }
            else if cal.isDateInYesterday(date) { yesterday.append(session) }
            else { earlier.append(session) }
        }
        return [("今天", today), ("昨天", yesterday), ("更早", earlier)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                screenHeader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("工作台").font(.largeTitle.bold()).foregroundStyle(Theme.text)
                            Text("从上次停下的地方，继续。")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 12)

                        ConnectionCard(loading: loading, failed: errorText != nil,
                                       total: sessions.count,
                                       running: sessions.count(where: { $0.running == true }),
                                       openSettings: { showSettings = true })
                        searchField
                        sessionContent
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await load() }
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("新建会话", systemImage: "plus") { if AppConfig.isConfigured { showNewSession = true } else { showSettings = true } }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 12).padding(.bottom, 10)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bg.opacity(0.97))
            }
            .navigationDestination(for: SessionSummary.self) { session in
                ChatView(session: session).id(session.sessionId)
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionView(preferredSessionId: UserDefaults.standard.string(forKey: lastSessionKey)) { id in
                    Task { await load(); openSession(id: id); await loadWorkspaces() }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await loadWorkspaces()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await load()
                if !initialLoadFinished {
                    initialLoadFinished = true
                    #if DEBUG
                    let args = ProcessInfo.processInfo.arguments
                    if let index = args.firstIndex(of: "--open-session"), index + 1 < args.count {
                        openSession(id: args[index + 1])
                    }
                    #endif
                    if path.isEmpty, let last = UserDefaults.standard.string(forKey: lastSessionKey),
                       let session = sessions.first(where: { $0.sessionId == last }) { path = [session] }
                }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    if path.isEmpty { await load() }
                }
            }
        }
        .onChange(of: path.last?.sessionId) { _, id in
            if let id { UserDefaults.standard.set(id, forKey: lastSessionKey) }
            else { Task { await load() } }
        }
        .onOpenURL { handleDeepLink($0) }
        .onReceive(NotificationCenter.default.publisher(for: .dshServerChanged)) { _ in
            path = []
            pendingSessionId = nil
            sessions = []
            workspaces = nil
            Task { await load() }
            Task { await loadWorkspaces() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dshOpenSession)) { note in
            if let id = note.object as? String { openSession(id: id) }
        }
    }

    private var screenHeader: some View {
        HStack(spacing: 11) {
            BrandMark()
            Text("DSH").font(.title3.weight(.bold).monospaced()).tracking(2)
                .foregroundStyle(Theme.text)
            Text("REMOTE").font(.caption.weight(.medium)).tracking(2)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("设置", systemImage: "slider.horizontal.3") { showSettings = true }
                .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, Theme.Space.screen)
        .padding(.top, 8).padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("搜索会话或工作目录", text: $query, prompt: Text("搜索会话或工作目录").foregroundStyle(Theme.muted))
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("搜索会话或工作目录")
            if !query.isEmpty {
                Button("清空搜索", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).foregroundStyle(Theme.muted)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 15).padding(.trailing, 8)
        .frame(minHeight: 50)
        .background(Theme.card, in: .rect(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.stroke) }
    }

    @ViewBuilder
    private var sessionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(query.isEmpty ? "最近会话" : "搜索结果").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Text("\(filtered.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            }
            if loading && sessions.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 19).fill(Theme.card).frame(height: 96)
                        .redacted(reason: .placeholder)
                }
            } else if let errorText, sessions.isEmpty {
                VStack(spacing: 18) {
                    EmptyState(icon: "wifi.exclamationmark", title: "暂时无法连接", detail: errorText)
                    Button("重新连接") { Task { await load() } }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(.vertical, 20)
            } else if filtered.isEmpty {
                EmptyState(icon: query.isEmpty ? "bubble.left.and.text.bubble.right" : "magnifyingglass",
                           title: query.isEmpty ? "下一段工作，从这里开始" : "没有找到匹配会话",
                           detail: query.isEmpty ? "新建会话，或继续 Mac 上的现有任务。" : "试试其他名称或目录关键词。")
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
                ForEach(groups, id: \.0) { title, items in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                            .padding(.leading, 2)
                        ForEach(items) { session in
                            NavigationLink(value: session) {
                                SessionRowView(session: session, desktopGroup: workspaces.map { items in
                                    items.first(where: { $0.sessionIds.contains(session.sessionId) })?.displayName ?? "未分组"
                                })
                            }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 数据

    private func loadWorkspaces() async {
        guard AppConfig.isConfigured else { return }
        let requestID = UUID()
        workspaceLoadID = requestID
        let server = AppConfig.baseURL
        do {
            let snapshot = try await RemoteClient.shared.workspaceSnapshot(baseURL: server)
            guard !Task.isCancelled, workspaceLoadID == requestID, server == AppConfig.baseURL else { return }
            workspaces = snapshot.items
        } catch {
            // Conversation access remains available when this optional directory lookup fails.
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "dshremote", url.host == "session", url.pathComponents.count == 2 else { return }
        openSession(id: url.lastPathComponent)
    }

    private func openSession(id: String) {
        guard AppConfig.isConfigured, !id.isEmpty else { return }
        UserDefaults.standard.set(id, forKey: lastSessionKey)
        pendingSessionId = nil
        if let session = sessions.first(where: { $0.sessionId == id }) {
            path = [session]
        } else {
            pendingSessionId = id
            Task { await load() }
        }
    }

    private func load() async {
        guard AppConfig.isConfigured else { errorText = "请先在连接设置中填写你的服务器和凭证。"; return }
        let requestID = UUID()
        loadID = requestID
        let server = AppConfig.baseURL
        loading = true
        defer { if loadID == requestID { loading = false } }
        do {
            let result = try await RemoteClient.shared.listSessions(baseURL: server)
            guard !Task.isCancelled, loadID == requestID, server == AppConfig.baseURL else { return }
            sessions = result.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            errorText = nil
            if let pending = pendingSessionId {
                pendingSessionId = nil
                if let session = sessions.first(where: { $0.sessionId == pending }) { path = [session] }
                else { errorText = "该会话暂不可用，请刷新列表后重试。" }
            }
        } catch {
            guard !Task.isCancelled, loadID == requestID, server == AppConfig.baseURL else { return }
            errorText = error.localizedDescription
        }
    }
}
