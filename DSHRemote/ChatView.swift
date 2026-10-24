import SwiftUI

struct ChatView: View {
    let session: SessionSummary
    private let onSidebar: (() -> Void)?
    private let sidebarVisible: Bool
    private let archived: Bool
    private let restoring: Bool
    private let canRestore: Bool
    private let onRestore: (() -> Void)?
    @StateObject private var stream: ChatStream
    @State private var input = ""
    @State private var sending = false
    @State private var images: [ImageAttachment] = []
    @State private var loadingImages = false
    @State private var imageError: String?
    @State private var draftRequestId = UUID().uuidString
    private let serverURL: URL
    @State private var showModels = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nearBottom = true
    @State private var scrolledInitially = false
    @State private var scrollHeight: CGFloat = 0

    init(session: SessionSummary, onSidebar: (() -> Void)? = nil, sidebarVisible: Bool = false, archived: Bool = false,
         restoring: Bool = false, canRestore: Bool = true, onRestore: (() -> Void)? = nil) {
        self.session = session
        self.onSidebar = onSidebar
        self.sidebarVisible = sidebarVisible
        self.archived = archived
        self.restoring = restoring
        self.canRestore = canRestore
        self.onRestore = onRestore
        let server = AppConfig.baseURL
        serverURL = server
        _stream = StateObject(wrappedValue: ChatStream(sessionId: session.sessionId, running: session.running == true, baseURL: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomArea }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showModels, onDismiss: {
            #if DEBUG
            if DesignPreview.enabled { return }
            #endif
            Task { await stream.refreshSessionMeta() }
        }) {
            ModelPickerView(sessionId: session.sessionId)
        }
        .task(id: scenePhase) {
            #if DEBUG
            if DesignPreview.enabled {
                stream.loadDesignPreview()
                if ProcessInfo.processInfo.arguments.contains("--show-models") { showModels = true }
                return
            }
            #endif
            guard scenePhase == .active else { stream.disconnect(); return }
            await stream.restoreCachedMessages()
            guard !Task.isCancelled else { return }
            stream.connect()
            await stream.loadMeta()
            await stream.refreshSessionMeta()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--show-models") { showModels = true }
            #endif
        }
        .onDisappear { stream.disconnect() }
        .onChange(of: input) { _, _ in draftRequestId = UUID().uuidString }
        .onChange(of: images.map(\.id)) { _, _ in draftRequestId = UUID().uuidString }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 6) {
            Button(onSidebar == nil ? "返回对话" : sidebarVisible ? "隐藏侧栏" : "打开侧栏",
                   systemImage: onSidebar == nil ? "chevron.left" : sidebarVisible ? "sidebar.left" : "line.3.horizontal") {
                inputFocused = false
                if let onSidebar { onSidebar() } else { dismiss() }
            }
                .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(stream.connected ? Theme.accent : Theme.warning).frame(width: 5, height: 5)
                    Text(archived ? "已归档" : stream.running ? "正在执行" : stream.connected ? "Mac 已连接" : "正在连接 Mac")
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1).layoutPriority(1)
                    if let cwd = session.cwd {
                        Text("·").foregroundStyle(Theme.muted)
                        Text((cwd as NSString).lastPathComponent)
                            .font(.caption.monospaced()).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Button("模型设置", systemImage: "slider.horizontal.3") { showModels = true }
                .labelStyle(.iconOnly).buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.top, 5).padding(.bottom, 8)
        .background(Theme.bg)
    }

    // MARK: - 消息

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if stream.hasMoreHistory {
                        Button {
                            Task { await stream.loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                if stream.loadingMore { ProgressView().controlSize(.mini) }
                                Text(stream.loadingMore ? "加载中…" : "加载更早的消息")
                            }
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.card, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(stream.loadingMore)
                    }

                    if stream.timelineMessages.isEmpty && stream.liveText.isEmpty {
                        EmptyState(icon: "bubble.left.and.text.bubble.right", title: stream.connected ? "开始对话" : "读取会话中",
                                   detail: stream.connected ? "发送消息，继续 Mac 上的任务。" : "正在同步历史消息…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }

                    ForEach(ChatTimelineItem.grouped(stream.timelineMessages)) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            if item.isToolGroup && item.messages.count > 1 {
                                ToolResultGroupView(messages: item.messages, sessionId: session.sessionId, serverURL: serverURL,
                                                    active: stream.connected && stream.running)
                            } else if let message = item.messages.first, item.isToolGroup {
                                ExecutionRow(message: message, sessionId: session.sessionId, serverURL: serverURL,
                                             active: stream.connected && stream.running)
                            } else if let message = item.messages.first {
                                MessageRow(message: message, sessionId: session.sessionId, serverURL: serverURL)
                            }
                        }
                        .id(item.id)
                    }

                    if !stream.liveText.isEmpty {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("正在回复…").font(.caption).foregroundStyle(Theme.muted)
                            }
                            RichText(text: stream.liveText).font(.body).lineSpacing(5).foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("live")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: Bool.self) { geometry in
                    geometry.frame(in: .named("chatScroll")).maxY <= scrollHeight + 80
                } action: { nearBottom = $0 }
            }
            .defaultScrollAnchor(.bottom)
            .coordinateSpace(.named("chatScroll"))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: stream.messages.last?.id) { _, id in
                guard id != nil else { return }
                if !scrolledInitially || nearBottom {
                    scrollToBottom(proxy)
                    scrolledInitially = true
                }
            }
            .onChange(of: stream.liveText) { _, _ in
                if nearBottom { scrollToBottom(proxy) }
            }
            .onChange(of: stream.liveReasoning) { _, _ in
                if nearBottom { scrollToBottom(proxy) }
            }
            .onChange(of: inputFocused) { _, focused in
                if focused && nearBottom { scrollToBottom(proxy) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom {
                    Button("回到最新消息", systemImage: "arrow.down") {
                        nearBottom = true
                        scrollToBottom(proxy)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
                    .padding(18)
                }
            }
        }
    }

    // MARK: - 底部

    private var bottomArea: some View {
        VStack(spacing: 12) {
            if !stream.connected {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(stream.showingCachedMessages ? "已显示本地记录，正在同步…" : stream.reconnecting ? "连接断开，正在重连…" : "连接中…")
                        .font(.caption)
                    Spacer()
                    Button("重连") { stream.retryNow() }
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.warning.opacity(0.06), in: .rect(cornerRadius: 14))
            }

            if !archived && (stream.pendingQuestions != nil || stream.pendingApproval != nil) {
                ScrollView {
                    VStack(spacing: 10) {
                        if let questions = stream.pendingQuestions {
                            QuestionCard(prompt: questions, submitting: stream.answeringQuestions) { answers in
                                stream.answerQuestions(answers)
                            }
                            .id(questions.id)
                            .disabled(!stream.connected)
                        }
                        if let approval = stream.pendingApproval {
                            ApprovalCard(prompt: approval,
                                         onAllow: { stream.answerApproval(allow: true) },
                                         onReject: { stream.answerApproval(allow: false) })
                                .disabled(stream.answeringApproval || !stream.connected)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = stream.errorText {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("关闭错误提示", systemImage: "xmark.circle.fill") { stream.errorText = nil }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
            }

            if archived {
                VStack(spacing: 12) {
                    Label("会话已归档，恢复后可以继续对话。", systemImage: "archivebox")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Button(restoring ? "正在恢复…" : "恢复会话") { onRestore?() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(restoring || !canRestore)
                }.padding(.vertical, 8)
            } else {
                ChatComposer(stream: stream, input: $input, images: $images, loadingImages: $loadingImages, imageError: $imageError,
                             sending: sending, focus: $inputFocused,
                             onSend: send, onModels: { showModels = true })
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8).padding(.bottom, 8)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(Theme.bg.opacity(0.98))
    }

    private func send() {
        #if DEBUG
        if DesignPreview.enabled { return }
        #endif
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || !images.isEmpty), !sending, !loadingImages, stream.connected else { return }
        let attachments = images
        let requestId = draftRequestId
        imageError = nil
        sending = true
        Task {
            defer { sending = false }
            if await stream.submitPrompt(text, images: attachments, requestId: requestId) {
                input = ""
                images = []
                nearBottom = true
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        #if DEBUG
        // Reproduce table layout issues against real history without sending a prompt.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-first-table") || arguments.contains("--show-last-table"),
           let message = stream.messages.last(where: { message in
               message.role == .assistant && MarkdownBlock.parse(message.text).contains { if case .table = $0.content { return true }; return false }
           }) {
            let tables = MarkdownBlock.parse(message.text).filter { if case .table = $0.content { return true }; return false }
            if let table = arguments.contains("--show-last-table") ? tables.last : tables.first {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    proxy.scrollTo("table:\(message.id):\(table.id)", anchor: .top)
                }
                return
            }
        }
        #endif
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
