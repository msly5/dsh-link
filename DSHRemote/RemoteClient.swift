import Foundation

struct RemoteError: LocalizedError {
    let message: String
    var code: String? = nil
    var errorDescription: String? { message }
}

actor RemoteClient {
    static let shared = RemoteClient()

    private let session: URLSession
    private let credentials: ConnectionProfile?

    init(session: URLSession = SecureTransport.session(), credentials: ConnectionProfile? = nil) {
        self.session = session
        self.credentials = credentials
    }

    func call(_ method: String, args: [String: Any], baseURL: URL? = nil, upload: Bool = false, credentials: ConnectionProfile? = nil) async throws -> Any {
        let server = baseURL ?? AppConfig.baseURL
        var req = URLRequest(url: server.appending(path: "api/\(method)"))
        req.httpMethod = "POST"
        req.timeoutInterval = upload ? 120 : 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in ((credentials ?? self.credentials)?.headers(for: server) ?? AppConfig.accessHeaders(for: server)) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let body: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": method,
            "payload": ["args": args],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        if upload {
            // A photo picker may stay open past the shared connection's idle lifetime.
            // Use a fresh upload connection and explicit body instead of reusing that idle task transport.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = session.configuration.protocolClasses
            configuration.urlCache = nil
            let uploader = SecureTransport.session(configuration: configuration)
            defer { uploader.finishTasksAndInvalidate() }
            (data, response) = try await uploader.upload(for: req, from: req.httpBody ?? Data())
        } else {
            (data, response) = try await session.data(for: req)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw RemoteError(message: RemoteClient.describe(status: status))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw RemoteError(message: "响应格式异常")
        }
        guard let ok = result["ok"] as? Bool else {
            throw RemoteError(message: "响应缺少调用结果，请检查服务器版本")
        }
        if !ok {
            let err = result["error"] as? [String: Any]
            let message = err?["message"] as? String ?? "调用失败"
            if message.contains("does not support image input") {
                throw RemoteError(message: "当前模型不支持图片，请切换到支持图片的模型后重试。")
            }
            throw RemoteError(message: message, code: err?["code"] as? String)
        }
        return result["value"] ?? [:]
    }

    static func describe(status: Int) -> String {
        switch status {
        case 301...308: return "服务器返回了重定向。请检查 HTTPS 地址和 Access Service Auth 策略。"
        case 401, 403: return "鉴权失败：Cloudflare Service Token 可能已失效"
        case 404: return "接口不存在，DSH 版本可能已更新"
        case 502, 503, 504: return "Mac 上的 DSH 不可达，确认桌面端在运行"
        default: return "请求失败（HTTP \(status)）"
        }
    }

    func sessionSnapshot(_ sessionId: String) async throws -> SessionSummary? {
        try await listSessions().first { $0.sessionId == sessionId }
    }

    func listSessions(baseURL: URL? = nil, credentials: ConnectionProfile? = nil) async throws -> [SessionSummary] {
        let value = try await call("session/list", args: ["_request": [:]], baseURL: baseURL, credentials: credentials)
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(SessionListValue.self, from: data).items
    }

    func setSessionArchived(_ sessionId: String, archived: Bool, stopActivity: Bool = false,
                            baseURL: URL? = nil) async throws -> [String] {
        guard !sessionId.isEmpty else { throw RemoteError(message: "会话标识不能为空") }
        var request: [String: Any] = ["sessionId": sessionId]
        if archived && stopActivity { request["stopActivity"] = true }
        let value = try await call(archived ? "workspace/archiveSession" : "workspace/unarchiveSession",
                                   args: ["request": request], baseURL: baseURL)
        let result = try JSONDecoder().decode(WorkspaceArchiveValue.self, from: JSONSerialization.data(withJSONObject: value))
        return result.archivedSessionIds
    }

    func prompt(sessionId: String, text: String, images: [ImageAttachment] = [], requestId: String = UUID().uuidString) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty else { throw RemoteError(message: "请先输入文字或选择图片。") }
        var content: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text]]
        content.append(contentsOf: images.map(\.content))
        let value = try await call("session/prompt", args: [
            "request": [
                "requestId": requestId,
                "sessionId": sessionId,
                "mode": "queue",
                "content": content,
                "clientTimeZone": TimeZone.current.identifier,
            ]
        ], upload: !images.isEmpty)
        guard (value as? [String: Any])?["accepted"] as? Bool == true else {
            throw RemoteError(message: "服务器未确认接收，文字和图片已保留，请稍后重试。")
        }
    }

    func imageAttachment(sessionId: String, attachmentId: String, baseURL: URL) async throws -> Data {
        let value = try await call("session/attachment", args: ["request": [
            "sessionId": sessionId, "attachmentId": attachmentId,
        ]], baseURL: baseURL, upload: true)
        guard let result = value as? [String: Any], let ref = result["attachment"] as? [String: Any],
              ref["attachmentId"] as? String == attachmentId,
              let encoded = result["data"] as? String, encoded.utf8.count <= 28 * 1024 * 1024,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
            throw RemoteError(message: "图片响应格式异常或图片过大。")
        }
        return data
    }

    func cancel(sessionId: String) async throws {
        _ = try await call("session/cancel", args: ["request": ["sessionId": sessionId]])
    }

    func workspaceSnapshot(baseURL: URL? = nil) async throws -> WorkspaceSnapshot {
        let server = baseURL ?? AppConfig.baseURL
        var request = URLRequest(url: AppConfig.webSocketURL(for: server))
        for (key, value) in AppConfig.accessHeaders(for: server) { request.setValue(value, forHTTPHeaderField: key) }
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: WorkspaceSnapshot.self) { group in
                group.addTask {
                    let open: [String: Any] = ["type": "open", "streamId": "workspaces", "endpoint": "workspace/follow", "payload": ["args": [:]]]
                    let data = try JSONSerialization.data(withJSONObject: open)
                    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let bytes): data = bytes
                        @unknown default: continue
                        }
                        if let snapshot = try WorkspaceSnapshot.decodeFrame(data) { return snapshot }
                    }
                    throw CancellationError()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    // Cancel the receive as well so the task group cannot wait forever.
                    socket.cancel(with: .goingAway, reason: nil)
                    throw RemoteError(message: "读取桌面工作区超时，请重试。")
                }
                defer { group.cancelAll() }
                guard let snapshot = try await group.next() else { throw CancellationError() }
                return snapshot
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }

    func resolveWorkspace(path: String, baseURL: URL? = nil) async throws -> DesktopWorkspace {
        let value = try await call("workspace/create", args: ["request": ["path": path]], baseURL: baseURL)
        guard let workspace = (value as? [String: Any])?["workspace"] as? [String: Any] else {
            throw RemoteError(message: "无法登记桌面工作区")
        }
        return try JSONDecoder().decode(DesktopWorkspace.self, from: JSONSerialization.data(withJSONObject: workspace))
    }

    func createSession(workspaceId: String, sessionId: String, baseURL: URL? = nil) async throws -> String {
        guard !workspaceId.isEmpty, !sessionId.isEmpty else { throw RemoteError(message: "请先选择桌面工作区") }
        let value = try await call("session/create", args: ["request": ["workspaceId": workspaceId, "sessionId": sessionId]], baseURL: baseURL)
        guard let dict = value as? [String: Any], let id = dict["sessionId"] as? String else {
            throw RemoteError(message: "创建会话失败")
        }
        return id
    }

    func permissionCatalog() async throws -> PermissionCatalog {
        let value = try await call("permissionPresets/catalog", args: [:])
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(PermissionCatalog.self, from: data)
    }

    /// 与桌面端聊天页相同：只切换当前会话的权限。
    func setPermission(sessionId: String, preset: String) async throws {
        let value = try await call("commands/execute", args: [
            "agentId": sessionId,
            "line": "/permission \(preset)",
            "submittedAttachments": [],
        ])
        guard let execution = value as? [String: Any],
              let result = execution["result"] as? [String: Any] else {
            throw RemoteError(message: "服务器不支持当前会话的权限切换")
        }
        if result["kind"] as? String != "success" {
            throw RemoteError(message: result["text"] as? String ?? "权限切换失败")
        }
    }

    func modelCatalog() async throws -> ModelCatalog {
        let value = try await call("session/modelCatalog", args: [:])
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    func selectModel(sessionId: String, provider: String, model: String, effort: String?) async throws {
        var request: [String: Any] = [
            "sessionId": sessionId,
            "provider": provider,
            "model": model,
        ]
        if let effort { request["reasoningEffort"] = effort }
        _ = try await call("session/selectModel", args: ["request": request])
    }

    /// 向前翻更早的历史；throughSeq 必须是 follow 开场快照给的 cursor
    func page(sessionId: String,
              throughSeq: Int,
              beforeSeq: Int?,
              maxMessages: Int) async throws -> (records: [[String: Any]], hasMore: Bool) {
        var request: [String: Any] = [
            "address": ["kind": "session", "sessionId": sessionId],
            "throughSeq": throughSeq,
            "maxMessages": maxMessages,
        ]
        if let beforeSeq { request["beforeSeq"] = beforeSeq }
        let value = try await call("session/page", args: ["request": request])
        guard let dict = value as? [String: Any], let records = dict["records"] as? [[String: Any]],
              let hasMore = dict["hasMore"] as? Bool else {
            throw RemoteError(message: "历史消息响应格式异常")
        }
        return (records, hasMore)
    }

    func passEvent(clientId: String, eventId: String) async throws {
        _ = try await call("$events/result", args: [
            "clientId": clientId, "eventId": eventId, "outcome": ["kind": "next"],
        ])
    }

    /// 回答一次 waterfall（审批 / 询问）
    func answer(clientId: String,
                eventId: String,
                value: Any?) async throws {
        var outcome: [String: Any] = ["kind": "result"]
        if let value { outcome["value"] = value }
        _ = try await call("$events/result", args: [
            "clientId": clientId,
            "eventId": eventId,
            "outcome": outcome,
        ])
    }
}
