import Combine
import Foundation

@MainActor
final class ChatStream: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var liveText = ""
    @Published private(set) var liveReasoning = ""
    @Published private(set) var connected = false
    @Published var errorText: String?
    @Published private(set) var running: Bool
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var loadingMore = false
    @Published private(set) var reconnecting = false
    @Published private(set) var showingCachedMessages = false
    @Published private(set) var imageLimits = ImageLimits.fallback
    @Published private(set) var permissionOptions: [PermissionOption] = []
    @Published private(set) var permissionPreset = "workspace-write"
    @Published private(set) var modelLabel = ""
    @Published private(set) var usageRatio: Double?
    @Published private(set) var sessionPermission: String?
    @Published private(set) var sessionModel = ""
    @Published private(set) var sessionEffort = ""
    @Published private(set) var modelGroups: [ModelProviderGroup] = []
    @Published private(set) var updatingSelection = false
    @Published private(set) var cancelling = false
    @Published private var approvals: [ApprovalPrompt] = []
    @Published private var questions: [QuestionPrompt] = []
    @Published private var answering = Set<String>()

    var pendingApproval: ApprovalPrompt? { approvals.first }
    var pendingQuestions: QuestionPrompt? { questions.first }
    var answeringApproval: Bool { pendingApproval.map { answering.contains($0.id) } ?? false }
    var answeringQuestions: Bool { pendingQuestions.map { answering.contains($0.id) } ?? false }

    var timelineMessages: [ChatMessage] {
        guard !liveReasoning.isEmpty else { return messages }
        return messages + [ChatMessage(id: "reasoning:" + (attemptId ?? "live"), seq: cursor + 1, role: .tool, text: liveReasoning,
                                       activity: ExecutionActivity(kind: .reasoning, phase: .running))]
    }

    private var task: URLSessionWebSocketTask?
    private var cursor = -1
    private var historyCursor = -1
    private var oldestSeq: Int?
    private var clientId: String?
    private var handledEventIds = Set<String>()
    private var followOpened = false
    private var retryAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var stopped = true
    private var activityRevision = 0
    private var historyGeneration = 0
    private let sessionId: String
    private let client: RemoteClient
    private let serverURL: URL
    private let cache: ConversationCache?
    private var restoredCache = false
    private var cacheSaveTask: Task<Void, Never>?
    private var selectionRevision = 0
    private var streamRevision = 0
    private var attemptId: String?
    private var nextChunkIndex = 0

    private static let socketSession = SecureTransport.session()

    init(sessionId: String, running: Bool = false, client: RemoteClient = .shared,
         baseURL: URL = AppConfig.baseURL, cache: ConversationCache? = .shared) {
        self.sessionId = sessionId
        self.running = running
        self.client = client
        self.serverURL = baseURL
        self.cache = cache
    }

    func restoreCachedMessages() async {
        guard !restoredCache, let cache else { return }
        let generation = historyGeneration
        let cached = await cache.load(server: serverURL, sessionId: sessionId)
        guard !Task.isCancelled, generation == historyGeneration else { return }
        restoredCache = true
        guard let snapshot = cached, cursor < 0, messages.isEmpty else { return }
        messages = snapshot.messages
        cursor = snapshot.cursor
        oldestSeq = snapshot.oldestSeq
        showingCachedMessages = !messages.isEmpty
    }

    func saveCachedMessages() async {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        guard historyCursor >= 0, let cache else { return }
        await cache.save(server: serverURL, sessionId: sessionId, cursor: cursor, oldestSeq: oldestSeq, messages: messages)
    }

    private func scheduleCacheSave(immediately: Bool = false) {
        guard let cache, historyCursor >= 0 else { return }
        cacheSaveTask?.cancel()
        let server = serverURL
        let id = sessionId
        let sequence = cursor
        let oldest = oldestSeq
        let completed = messages
        let recordedAt = Date()
        // Capture values so a popped ChatView can finish saving without retaining its stream.
        cacheSaveTask = Task {
            if !immediately {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await cache.save(server: server, sessionId: id, cursor: sequence, oldestSeq: oldest,
                             messages: completed, recordedAt: recordedAt)
        }
    }

    func connect() {
        stopped = false
        reconnectTask?.cancel()
        timeoutTask?.cancel()
        heartbeatTask?.cancel()
        // Clear the reference first: callbacks from an old socket must be ignored.
        let previous = task
        task = nil
        previous?.cancel(with: .goingAway, reason: nil)
        connected = false
        clientId = nil
        followOpened = false
        handledEventIds.removeAll()
        approvals.removeAll()
        questions.removeAll()
        answering.removeAll()
        historyGeneration += 1

        var request = URLRequest(url: AppConfig.webSocketURL(for: serverURL))
        for (key, value) in AppConfig.accessHeaders(for: serverURL) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let socket = SecureTransport.webSocketTask(session: Self.socketSession, request: request)
        task = socket
        socket.resume()
        send(socket, ["type": "open", "streamId": "events", "endpoint": "$events", "payload": ["args": [:]]])
        receive(socket)
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.task === socket, !self.connected else { return }
            self.connectionFailed(socket, message: "连接超时，正在重新连接…")
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                guard let self, self.task === socket else { return }
                socket.sendPing { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.connectionFailed(socket, message: error.localizedDescription) }
                }
            }
        }
    }

    func disconnect() {
        scheduleCacheSave(immediately: true)
        stopped = true
        reconnectTask?.cancel()
        timeoutTask?.cancel()
        heartbeatTask?.cancel()
        reconnectTask = nil
        timeoutTask = nil
        heartbeatTask = nil
        let previous = task
        task = nil
        previous?.cancel(with: .goingAway, reason: nil)
        connected = false
        reconnecting = false
        clientId = nil
        historyGeneration += 1
    }

    func retryNow() {
        retryAttempt = 0
        reconnecting = true
        connect()
    }

    private func connectionFailed(_ socket: URLSessionWebSocketTask, message: String) {
        guard task === socket, !stopped else { return }
        task = nil
        socket.cancel(with: .goingAway, reason: nil)
        timeoutTask?.cancel()
        heartbeatTask?.cancel()
        connected = false
        clientId = nil
        errorText = message
        reconnecting = true
        let delay = min(pow(2, Double(retryAttempt)), 15)
        retryAttempt = min(retryAttempt + 1, 5)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !self.stopped else { return }
            self.connect()
        }
    }

    private func send(_ socket: URLSessionWebSocketTask, _ frame: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: frame)
            guard let text = String(data: data, encoding: .utf8) else { return }
            socket.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.connectionFailed(socket, message: error.localizedDescription) }
            }
        } catch { connectionFailed(socket, message: error.localizedDescription) }
    }

    private func receive(_ socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === socket, !self.stopped else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { self.handle(text) }
                    @unknown default: break
                    }
                    if self.task === socket { self.receive(socket) }
                case .failure(let error): self.connectionFailed(socket, message: error.localizedDescription)
                }
            }
        }
    }

    // Internal so protocol fixtures can exercise the same decoder used by the socket.
    func handle(_ json: String) {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let value = root["value"] as? [String: Any] ?? root
        guard let type = value["type"] as? String else { return }
        switch type {
        case "ready":
            if let id = value["clientId"] as? String { clientId = id }
            if !followOpened, let socket = task {
                followOpened = true
                send(socket, [
                    "type": "open", "streamId": "follow", "endpoint": "session/follow",
                    "payload": ["args": ["request": [
                        "address": ["kind": "session", "sessionId": sessionId],
                        "maxMessages": 20, "assistantStream": true,
                    ]]],
                ])
            }
        case "snapshot":
            let previousCursor = cursor
            cursor = value["cursor"] as? Int ?? -1
            historyCursor = cursor
            historyGeneration += 1
            let records = value["records"] as? [[String: Any]] ?? []
            let parsed = parseMessages(records)
            let first = recordSequences(records).min()
            let serverHasMore = value["hasMore"] as? Bool ?? false
            // Preserve history only when the new page overlaps it; otherwise a gap would be hidden.
            if serverHasMore, previousCursor >= 0, cursor >= previousCursor, let first,
               first <= previousCursor || first - previousCursor == 1 {
                messages = merged(messages.filter { $0.seq < first }, parsed)
                oldestSeq = [oldestSeq, first].compactMap { $0 }.min()
            } else {
                messages = merged([], parsed)
                oldestSeq = first
            }
            showingCachedMessages = false
            hasMoreHistory = (oldestSeq ?? 0) > 0 && serverHasMore
            if let values = (value["projections"] as? [String: Any])?["values"] as? [String: Any] {
                applyProjection(values)
            }
            for record in records {
                guard let event = EventParser.event(from: record) else { continue }
                applyActivity(event)
            }
            restoreAssistant(value["assistantStream"] as? [String: Any])
            if attemptId != nil { running = true }
            connected = true
            reconnecting = false
            retryAttempt = 0
            errorText = nil
            timeoutTask?.cancel()
            scheduleCacheSave()
        case "event":
            guard let event = value["event"] as? [String: Any] else { return }
            let seq = event["seq"] as? Int ?? cursor + 1
            guard seq > cursor else { return }
            cursor = seq
            applyActivity(event)
            let rows = EventParser.displayMessages(from: event, fallbackSeq: seq)
            messages = merged(messages, rows)
            if event["type"] as? String == "assistant/message" {
                liveReasoning = ""
                if rows.contains(where: { $0.role == .assistant }) { liveText = "" }
            }
            if event["type"] as? String == "turn/end" {
                Task { await refreshSessionMeta() }
            }
            scheduleCacheSave()
        case "assistant-stream":
            if let frame = value["frame"] as? [String: Any] { applyAssistantFrame(frame) }
        case "waterfall": handleWaterfall(value)
        case "cancel":
            guard let id = value["eventId"] as? String else { return }
            approvals.removeAll { $0.id == id }
            questions.removeAll { $0.id == id }
        case "emit":
            if value["event"] as? String == "api-session/status",
               let args = value["args"] as? [Any], args.count >= 2,
               args[0] as? String == sessionId, let active = args[1] as? Bool {
                activityRevision += 1
                running = active
                if !active { liveText = ""; liveReasoning = "" }
            }
        case "error", "end":
            let message = (value["error"] as? [String: Any])?["message"] as? String
                ?? value["message"] as? String ?? "消息流已断开"
            if let socket = task { connectionFailed(socket, message: message) }
            else { errorText = message }
        default: break
        }
    }

    private func applyActivity(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "turn/start", "step/start": running = true
        case "turn/end": running = false; liveText = ""; liveReasoning = ""; attemptId = nil
        default: return
        }
        activityRevision += 1
    }

    private func restoreAssistant(_ baseline: [String: Any]?) {
        streamRevision = baseline?["revision"] as? Int ?? 0
        let attempt = baseline?["activeAttempt"] as? [String: Any]
        attemptId = attempt?["attemptId"] as? String
        nextChunkIndex = attempt?["nextIndex"] as? Int ?? 0
        liveText = EventParser.streamText(attempt?["stream"] as? [[String: Any]])
        liveReasoning = EventParser.streamText(attempt?["stream"] as? [[String: Any]], kind: "reasoning")
    }

    private func applyAssistantFrame(_ frame: [String: Any]) {
        let revision = frame["revision"] as? Int
        if let revision {
            if frame["type"] as? String == "start", revision == 1 { streamRevision = 0 }
            guard revision > streamRevision else { return }
            if revision != streamRevision + 1 {
                // A missing chunk cannot be reconstructed by appending. Fetch a new baseline.
                retryNow()
                return
            }
            streamRevision = revision
        }
        switch frame["type"] as? String {
        case "start":
            attemptId = frame["attemptId"] as? String
            nextChunkIndex = 0
            liveText = ""
            liveReasoning = ""
            running = true
            activityRevision += 1
        case "chunk":
            if let id = frame["attemptId"] as? String, id != attemptId { return }
            if let index = frame["index"] as? Int {
                guard index == nextChunkIndex else { retryNow(); return }
                nextChunkIndex += 1
            }
            if let chunk = frame["chunk"] as? [String: Any], let text = chunk["text"] as? String {
                if chunk["type"] as? String == "text-delta" { liveText += text }
                if chunk["type"] as? String == "reasoning-delta" { liveReasoning += text }
            }
        case "end": attemptId = nil
        default: break
        }
    }

    private func handleWaterfall(_ value: [String: Any]) {
        guard let event = value["event"] as? String, let id = value["eventId"] as? String,
              let request = value["request"] as? [String: Any], handledEventIds.insert(id).inserted else { return }
        guard value["agentId"] as? String == sessionId else {
            passEvent(id)
            return
        }
        switch event {
        case "user-questions/request":
            let parsed = (request["questions"] as? [[String: Any]] ?? []).compactMap { item -> UserQuestion? in
                guard let id = item["id"] as? String, let text = item["question"] as? String else { return nil }
                let options = (item["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
                return UserQuestion(id: id, header: item["header"] as? String, question: text,
                                    options: options, multiSelect: item["multiSelect"] as? Bool ?? false,
                                    detail: item["detail"] as? String)
            }
            if parsed.isEmpty { passEvent(id) }
            else { questions.append(QuestionPrompt(id: id, questions: parsed)) }
        case "approval/request":
            approvals.append(ApprovalPrompt(id: id, toolName: request["toolName"] as? String ?? "工具调用",
                                            reason: request["reason"] as? String))
        default: passEvent(id)
        }
    }

    private func passEvent(_ id: String) {
        guard let clientId else { return }
        Task {
            do { try await client.passEvent(clientId: clientId, eventId: id) }
            catch { errorText = error.localizedDescription }
        }
    }

    func answerApproval(allow: Bool) {
        guard let prompt = pendingApproval, let clientId, connected,
              answering.insert(prompt.id).inserted else { return }
        errorText = nil
        Task {
            defer { answering.remove(prompt.id) }
            do {
                try await client.answer(clientId: clientId, eventId: prompt.id, value: allow ? "allowed-once" : "rejected")
                approvals.removeAll { $0.id == prompt.id }
            } catch { errorText = error.localizedDescription }
        }
    }

    func answerQuestions(_ answers: [QuestionAnswer]) {
        guard let prompt = pendingQuestions, let clientId, connected,
              prompt.questions.allSatisfy({ question in
                  answers.contains { $0.id == question.id && $0.isComplete(for: question) }
              }), answering.insert(prompt.id).inserted else { return }
        errorText = nil
        Task {
            defer { answering.remove(prompt.id) }
            do {
                try await client.answer(clientId: clientId, eventId: prompt.id, value: ["answers": answers.map(\.payload)])
                questions.removeAll { $0.id == prompt.id }
            } catch { errorText = error.localizedDescription }
        }
    }

    func submitPrompt(_ text: String, images: [ImageAttachment] = [], requestId: String = UUID().uuidString) async -> Bool {
        guard connected else { errorText = "连接恢复后再发送，输入内容已保留。"; return false }
        errorText = nil
        do {
            try imageLimits.validate(images)
            let revision = activityRevision
            try await client.prompt(sessionId: sessionId, text: text, images: images, requestId: requestId)
            if revision == activityRevision { running = true }
            return true
        } catch {
            if (error as? URLError)?.code == .timedOut {
                errorText = "发送超时，文字和图片已保留，请检查网络后重试。"
            } else { errorText = error.localizedDescription }
            return false
        }
    }

    func cancel() async {
        guard !cancelling else { return }
        cancelling = true
        defer { cancelling = false }
        do { try await client.cancel(sessionId: sessionId) }
        catch { errorText = error.localizedDescription }
    }

    func loadMeta() async {
        do {
            let catalog = try await client.permissionCatalog()
            permissionOptions = catalog.options
            permissionPreset = catalog.defaultPreset
        } catch { errorText = "权限目录：\(error.localizedDescription)" }
        do {
            let catalog = try await client.modelCatalog()
            modelGroups = catalog.groups
            modelLabel = catalog.default.model
        } catch { errorText = "模型目录：\(error.localizedDescription)" }
    }

    func refreshSessionMeta() async {
        let revision = activityRevision
        let metaRevision = selectionRevision
        do {
            guard let summary = try await client.sessionSnapshot(sessionId) else { return }
            if revision == activityRevision, let active = summary.running { running = active }
            if metaRevision == selectionRevision && !updatingSelection { applySummary(summary) }
        } catch {
            if !connected { errorText = error.localizedDescription }
        }
    }

    private func applySummary(_ summary: SessionSummary) {
        if let limits = summary.projections?.values?.imageLimits { imageLimits = limits }
        usageRatio = summary.projections?.values?.contextPressure?.ratio
        sessionPermission = summary.projections?.values?.permissions?.currentValue
        let selection = summary.projections?.values?.modelSelection
        sessionModel = selection?.next?.model ?? selection?.lastUsed?.model ?? ""
        sessionEffort = selection?.next?.reasoningEffort ?? selection?.lastUsed?.reasoningEffort ?? ""
    }

    private func applyProjection(_ values: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let projection = try? JSONDecoder().decode(ProjectionValues.self, from: data) else { return }
        if let limits = projection.imageLimits { imageLimits = limits }
        usageRatio = projection.contextPressure?.ratio
        sessionPermission = projection.permissions?.currentValue
        let selection = projection.modelSelection?.next ?? projection.modelSelection?.lastUsed
        sessionModel = selection?.model ?? ""
        sessionEffort = selection?.reasoningEffort ?? ""
    }

    func selectModel(provider: String, model: String, effort: String?) async {
        guard !updatingSelection else { return }
        updatingSelection = true
        selectionRevision += 1
        defer { updatingSelection = false }
        do {
            try await client.selectModel(sessionId: sessionId, provider: provider, model: model, effort: effort)
            sessionModel = model
            sessionEffort = effort ?? ""
        } catch { errorText = error.localizedDescription }
    }

    func setPermission(_ value: String) async {
        guard !updatingSelection else { return }
        updatingSelection = true
        selectionRevision += 1
        defer { updatingSelection = false }
        do {
            try await client.setPermission(sessionId: sessionId, preset: value)
            sessionPermission = value
        } catch { errorText = error.localizedDescription }
    }

    func loadMore() async {
        guard connected, !loadingMore, hasMoreHistory, let oldest = oldestSeq, historyCursor >= 0 else { return }
        loadingMore = true
        let generation = historyGeneration
        defer { loadingMore = false }
        do {
            let result = try await client.page(sessionId: sessionId, throughSeq: historyCursor, beforeSeq: oldest, maxMessages: 20)
            guard generation == historyGeneration else { return }
            messages = merged(parseMessages(result.records), messages)
            let next = recordSequences(result.records).min()
            if let next, next < oldest { oldestSeq = next }
            hasMoreHistory = result.hasMore && next != nil && (next ?? oldest) < oldest
            scheduleCacheSave()
        } catch { errorText = error.localizedDescription }
    }

    private func recordSequences(_ records: [[String: Any]]) -> [Int] {
        records.compactMap { EventParser.event(from: $0)?["seq"] as? Int }
    }

    private func parseMessages(_ records: [[String: Any]]) -> [ChatMessage] {
        records.enumerated().flatMap { index, record -> [ChatMessage] in
            guard let event = EventParser.event(from: record) else { return [] }
            return EventParser.displayMessages(from: event, fallbackSeq: index)
        }
    }

    private func merged(_ first: [ChatMessage], _ second: [ChatMessage]) -> [ChatMessage] {
        var byID: [String: ChatMessage] = [:]
        for message in first + second {
            byID[message.id] = byID[message.id].map { $0.combiningExecution(message) } ?? message
        }
        return byID.values.sorted { $0.seq == $1.seq ? $0.id > $1.id : $0.seq < $1.seq }
    }
}

#if DEBUG && canImport(UIKit)
extension ChatStream {
    func loadDesignPreview() {
        messages = DesignPreview.messages
        connected = true
        running = false
        modelLabel = "DeepSeek"
        sessionModel = "DeepSeek"
        sessionEffort = ""
        usageRatio = 0.22
        permissionOptions = []
        errorText = nil
    }
}
#endif
