import SwiftUI

struct SessionListView: View {
    private enum Screen { case home, conversations, workspaces, archived }
    @State private var sessions: [SessionSummary] = []
    @State private var workspaces: [DesktopWorkspace]?
    @State private var archivedSessionIDs: Set<String> = []
    @State private var workspaceError: String?
    @State private var updatingSessionID: String?
    @State private var archiveRequestID = UUID()
    @State private var pendingArchive: SessionSummary?
    @State private var archiveError: String?
    @State private var workspaceLoadID = UUID()
    @State private var path: [SessionSummary] = []
    @State private var pendingSessionId: String?
    @State private var loading = false
    @State private var errorText: String?
    @State private var showSettings = false
    @State private var pairingURL: URL?
    @State private var sidebarOpen = false
    @State private var expandedLayout = false
    @State private var screen: Screen = .home
    @State private var selectedWorkspace: DesktopWorkspace?
    @State private var query = ""
    @State private var showNewSession = false
    @State private var initialLoadFinished = false
    @State private var loadID = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lastSessionKey: String { "lastSessionId." + AppConfig.baseURL.absoluteString }
    private var previewing: Bool {
        #if DEBUG
        return DesignPreview.enabled
        #else
        return false
        #endif
    }
    private var filtered: [SessionSummary] {
        sessions.filter { session in
            archivedSessionIDs.contains(session.id) == (screen == .archived) &&
            (selectedWorkspace.map { $0.sessionIds.contains(session.id) } ?? true) &&
            (query.isEmpty || session.title.localizedStandardContains(query) || (session.cwd ?? "").localizedStandardContains(query))
        }
    }
    private var activeSessions: [SessionSummary] { sessions.filter { !archivedSessionIDs.contains($0.id) } }
    private var archiveActionsEnabled: Bool { updatingSessionID == nil && workspaces != nil && workspaceError == nil }
    private var archiveConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } })
    }
    private var archiveErrorPresented: Binding<Bool> {
        Binding(get: { archiveError != nil }, set: { if !$0 { archiveError = nil } })
    }
    var body: some View {
        SidebarContainer(isPresented: $sidebarOpen, isExpandedLayout: $expandedLayout) {
            SessionSidebar(sessions: activeSessions, workspaces: workspaces, archivedCount: archivedSessionIDs.count,
                           currentSessionID: path.last?.id, loading: loading,
                           conversationsSelected: (screen == .home || screen == .conversations) && path.isEmpty,
                           workspacesSelected: screen == .workspaces && path.isEmpty,
                           archivedSelected: screen == .archived && path.isEmpty,
                           updatingSessionID: updatingSessionID, actionsEnabled: archiveActionsEnabled,
                           onClose: { setSidebar(false) },
                           onConversations: { selectedWorkspace = nil; navigate(.conversations) },
                           onWorkspaces: { navigate(.workspaces) },
                           onWorkspace: { selectedWorkspace = $0; navigate(.conversations) },
                           onArchived: { selectedWorkspace = nil; navigate(.archived) }, onSettings: { showSettings = true },
                           onNew: newConversation,
                           onSelect: { id in openSession(id: id); dismissSidebarIfNeeded() }, onArchive: requestArchive)
        } content: {
            NavigationStack(path: $path) {
                mainPage
                    .navigationDestination(for: SessionSummary.self) { session in
                        ChatView(session: session, onSidebar: toggleSidebar, sidebarVisible: expandedLayout && sidebarOpen,
                                 archived: archivedSessionIDs.contains(session.id),
                                 restoring: updatingSessionID == session.id, canRestore: archiveActionsEnabled,
                                 onRestore: { requestArchive(session) }).id(session.id)
                    }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionView(preferredSessionId: selectedWorkspace?.sessionIds.first ?? UserDefaults.standard.string(forKey: lastSessionKey)) { id in
                Task { await refresh(); openSession(id: id) }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { pairingURL = nil }) { SettingsView(pairingURL: pairingURL) }
        .task(id: scenePhase) { await refreshWhileActive() }
        .onChange(of: path.last?.sessionId) { _, id in
            guard !previewing else { return }
            if let id { UserDefaults.standard.set(id, forKey: lastSessionKey) }
            else { Task { await load() } }
        }
        .onChange(of: sidebarOpen) { _, open in
            guard open else { return }
            refreshSidebar()
        }
        .onOpenURL { handleDeepLink($0) }
        .onReceive(NotificationCenter.default.publisher(for: .dshServerChanged)) { _ in
            resetForChangedServer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dshOpenSession)) { note in
            if let id = note.object as? String { openSession(id: id); dismissSidebarIfNeeded() }
        }
        .confirmationDialog("归档并停止会话？", isPresented: archiveConfirmationPresented, presenting: pendingArchive) { session in
            Button("停止并归档", role: .destructive) { Task { await setArchived(session, archived: true, stopActivity: true) } }
        } message: { _ in
            Text("这会停止该会话正在运行的任务、子任务及其后台活动。聊天记录会保留，之后可以恢复会话。")
        }
        .alert("操作未完成", isPresented: archiveErrorPresented, presenting: archiveError) { _ in } message: { Text($0) }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button(!expandedLayout && selectedWorkspace != nil && screen == .conversations ? "返回工作区" : expandedLayout && sidebarOpen ? "隐藏侧栏" : "打开侧栏",
                       systemImage: !expandedLayout && selectedWorkspace != nil && screen == .conversations ? "chevron.left" : expandedLayout ? "sidebar.left" : "line.3.horizontal") {
                    if !expandedLayout && selectedWorkspace != nil && screen == .conversations { selectedWorkspace = nil; screen = .workspaces; query = "" }
                    else { toggleSidebar() }
                }
                    .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
                Spacer()
                Text(screen == .home ? "dsh link" : screen == .workspaces ? "工作区" : screen == .archived ? "已归档" : selectedWorkspace?.displayName ?? "对话")
                    .font(screen == .home ? .system(.headline, design: .serif) : .headline)
                    .foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Button("新建对话", systemImage: "square.and.pencil", action: newConversation)
                    .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
            }.padding(.horizontal, 12).padding(.vertical, 6)
            if screen == .home {
                ConversationWelcome(isConfigured: AppConfig.isConfigured || previewing,
                                    serverLabel: previewing ? "Mac 已连接" : AppConfig.isConfigured ? AppConfig.baseURL.host ?? "连接设置" : "连接你的 Mac",
                                    onNew: newConversation, onSettings: { showSettings = true })
            }
            else if screen == .workspaces {
                WorkspaceBrowser(workspaces: workspaces, archivedSessionIDs: archivedSessionIDs, errorText: workspaceError, onRefresh: refresh) { workspace in
                    selectedWorkspace = workspace; screen = .conversations; query = ""
                }
            }
            else {
                SessionBrowser(sessions: sessions, filtered: filtered, workspaces: workspaces, loading: loading,
                               errorText: errorText, workspaceError: workspaceError, archived: screen == .archived,
                               updatingSessionID: updatingSessionID, actionsEnabled: archiveActionsEnabled,
                               query: $query, onRefresh: refresh, onSelect: { openSession(id: $0) }, onArchive: requestArchive)
            }
        }
        .background(Theme.bg).toolbar(.hidden, for: .navigationBar)
    }

    private func setSidebar(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { sidebarOpen = value }
    }
    private func toggleSidebar() { setSidebar(expandedLayout ? !sidebarOpen : true) }
    private func dismissSidebarIfNeeded() { if !expandedLayout { setSidebar(false) } }
    private func navigate(_ destination: Screen) {
        path = []; screen = destination; query = ""; dismissSidebarIfNeeded()
    }
    private func newConversation() {
        dismissSidebarIfNeeded()
        if AppConfig.isConfigured || previewing { showNewSession = true }
        else { showSettings = true }
    }

    // Keep asynchronous state changes outside the view builder so older
    // Swift compilers can type-check the navigation and presentation chain.
    private func refreshWhileActive() async {
        guard scenePhase == .active else { return }
        await refresh()
        if !initialLoadFinished {
            initialLoadFinished = true
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if DesignPreview.enabled {
                if args.contains("--preview-chat"), let first = sessions.first { path = [first] }
                if args.contains("--preview-conversations") { screen = .conversations }
                if args.contains("--preview-workspaces") { screen = .workspaces }
                if args.contains("--preview-archived") { screen = .archived }
                if args.contains("--preview-new") { showNewSession = true }
                if args.contains("--preview-settings") { showSettings = true }
                if args.contains("--preview-sidebar") { sidebarOpen = true }
                return
            }
            if let index = args.firstIndex(of: "--open-session"), index + 1 < args.count { openSession(id: args[index + 1]) }
            #endif
            if !AppConfig.isConfigured { showSettings = true }
            if path.isEmpty, let last = UserDefaults.standard.string(forKey: lastSessionKey),
               let session = activeSessions.first(where: { $0.id == last }) { path = [session] }
        }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            if path.isEmpty || sidebarOpen { await refresh() }
        }
    }

    private func refreshSidebar() {
        Task { await load() }
        Task { await loadWorkspaces() }
    }

    private func resetForChangedServer() {
        path = []; pendingSessionId = nil; sessions = []; workspaces = nil; selectedWorkspace = nil
        archivedSessionIDs = []; workspaceError = nil; archiveRequestID = UUID(); updatingSessionID = nil
        pendingArchive = nil; archiveError = nil; workspaceLoadID = UUID()
        refreshSidebar()
    }

    // MARK: - 数据

    private func refresh() async {
        await load()
        await loadWorkspaces()
    }

    private func requestArchive(_ session: SessionSummary) {
        guard archiveActionsEnabled else { return }
        if archivedSessionIDs.contains(session.id) { Task { await setArchived(session, archived: false) } }
        else if session.running == true { pendingArchive = session }
        else { Task { await setArchived(session, archived: true) } }
    }

    private func setArchived(_ session: SessionSummary, archived: Bool, stopActivity: Bool = false) async {
        guard updatingSessionID == nil else { return }
        let requestID = UUID()
        archiveRequestID = requestID
        updatingSessionID = session.id
        workspaceLoadID = UUID() // Discard snapshots started before this mutation.
        let server = AppConfig.baseURL
        do {
            let ids: [String]
            if previewing {
                var result = archivedSessionIDs
                if archived { result.insert(session.id) } else { result.remove(session.id) }
                ids = Array(result)
            } else {
                ids = try await RemoteClient.shared.setSessionArchived(session.id, archived: archived, stopActivity: stopActivity, baseURL: server)
            }
            guard archiveRequestID == requestID, server == AppConfig.baseURL else { return }
            archivedSessionIDs = Set(ids)
            if archived && path.contains(where: { $0.id == session.id }) {
                path = []; screen = .conversations
            }
            if archived && UserDefaults.standard.string(forKey: lastSessionKey) == session.id && !previewing {
                UserDefaults.standard.removeObject(forKey: lastSessionKey)
            }
            updatingSessionID = nil
            await refresh()
        } catch {
            guard archiveRequestID == requestID, server == AppConfig.baseURL else { return }
            updatingSessionID = nil
            if (error as? RemoteError)?.code == "workspace/session-active" && archived && !stopActivity {
                pendingArchive = session
            } else { archiveError = error.localizedDescription }
        }
    }

    private func loadWorkspaces() async {
        #if DEBUG
        if DesignPreview.enabled {
            if workspaces == nil { archivedSessionIDs = Set(DesignPreview.archivedSessionIds) }
            workspaces = DesignPreview.workspaces; workspaceError = nil; return
        }
        #endif
        guard AppConfig.isConfigured, updatingSessionID == nil else { return }
        let requestID = UUID()
        workspaceLoadID = requestID
        let server = AppConfig.baseURL
        do {
            let snapshot = try await RemoteClient.shared.workspaceSnapshot(baseURL: server)
            guard !Task.isCancelled, workspaceLoadID == requestID, server == AppConfig.baseURL else { return }
            workspaces = snapshot.items
            if let selectedWorkspace { self.selectedWorkspace = snapshot.items.first { $0.id == selectedWorkspace.id } }
            archivedSessionIDs = Set(snapshot.archivedSessionIds)
            workspaceError = nil
        } catch {
            guard !Task.isCancelled, workspaceLoadID == requestID, server == AppConfig.baseURL else { return }
            workspaceError = error.localizedDescription
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme?.lowercased() == "dshremote", url.host?.lowercased() == "configure" {
            pairingURL = url; dismissSidebarIfNeeded(); showSettings = true; return
        }
        guard url.scheme == "dshremote", url.host == "session", url.pathComponents.count == 2 else { return }
        openSession(id: url.lastPathComponent)
    }

    private func openSession(id: String) {
        guard (AppConfig.isConfigured || previewing), !id.isEmpty else { return }
        if !previewing { UserDefaults.standard.set(id, forKey: lastSessionKey) }
        pendingSessionId = nil
        if let session = sessions.first(where: { $0.sessionId == id }) {
            path = [session]
        } else {
            pendingSessionId = id
            Task { await load() }
        }
    }

    private func load() async {
        #if DEBUG
        if DesignPreview.enabled { sessions = DesignPreview.sessions; errorText = nil; return }
        #endif
        guard AppConfig.isConfigured else { errorText = nil; return }
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
