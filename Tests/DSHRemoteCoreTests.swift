import Foundation
import XCTest
@testable import DSHRemoteCore

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@MainActor
final class DSHRemoteCoreTests: XCTestCase {
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> RemoteClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return RemoteClient(session: URLSession(configuration: config))
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func ok(_ value: Any = [:]) -> (Int, [String: Any]) {
        (200, ["result": ["ok": true, "value": value]])
    }

    private func frame(_ value: [String: Any], into stream: ChatStream) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        stream.handle(String(decoding: data, as: UTF8.self))
    }

    private func message(_ seq: Int, _ role: String = "assistant", text: String = "hello") -> [String: Any] {
        let content: [[String: Any]] = [["type": "text", "text": text]]
        let data: [String: Any] = role == "user" ? ["content": content] : ["message": ["content": content]]
        return ["type": "\(role)/message", "seq": seq, "data": data]
    }

    private func snapshot(_ stream: ChatStream, cursor: Int = 10, records: [[String: Any]] = [], hasMore: Bool = false) throws {
        try frame(["type": "ready", "clientId": "client"], into: stream)
        try frame(["type": "snapshot", "cursor": cursor, "records": records, "hasMore": hasMore], into: stream)
    }

    private func approval(_ stream: ChatStream, id: String, agent: String = "mine") throws {
        try frame(["type": "waterfall", "event": "approval/request", "eventId": id,
                   "agentId": agent, "request": ["toolName": "shell", "reason": "review"]], into: stream)
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Async action did not settle")
    }

    func testCreateSessionRegistersDesktopWorkspaceAndKeepsRetryIdentity() async throws {
        var attempts = 0
        let remote = client { request in
            attempts += 1
            XCTAssertEqual(request.url?.host, "workspace.example")
            XCTAssertEqual(request.url?.path, "/api/session/create")
            let root = try self.body(request)
            let args = try XCTUnwrap((root["payload"] as? [String: Any])?["args"] as? [String: Any])
            let value = try XCTUnwrap(args["request"] as? [String: Any])
            XCTAssertEqual(value["workspaceId"] as? String, "desktop-workspace")
            XCTAssertEqual(value["sessionId"] as? String, "session-stable")
            XCTAssertNil(value["cwd"], "The host rejects workspaceId together with cwd")
            if attempts == 1 { throw URLError(.networkConnectionLost) }
            return self.ok(["sessionId": "session-stable"])
        }
        let server = URL(string: "https://workspace.example")!
        do {
            _ = try await remote.createSession(workspaceId: "desktop-workspace", sessionId: "session-stable", baseURL: server)
            XCTFail("Connection failure must remain visible for retry")
        } catch { }
        let id = try await remote.createSession(workspaceId: "desktop-workspace", sessionId: "session-stable", baseURL: server)
        XCTAssertEqual(id, "session-stable")
        XCTAssertEqual(attempts, 2)
    }

    func testCreateSessionRequiresDesktopWorkspace() async {
        let remote = client { _ in XCTFail("Do not create an ungrouped session"); return self.ok() }
        do {
            _ = try await remote.createSession(workspaceId: "", sessionId: "session-test")
            XCTFail("Missing workspace must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("工作区")) }
    }

    func testCustomDirectoryResolvesWorkspaceBeforeSessionCreation() async throws {
        var methods: [String] = []
        let remote = client { request in
            let root = try self.body(request)
            let method = try XCTUnwrap(root["method"] as? String)
            methods.append(method)
            let args = try XCTUnwrap((root["payload"] as? [String: Any])?["args"] as? [String: Any])
            let value = try XCTUnwrap(args["request"] as? [String: Any])
            if method == "workspace/create" {
                XCTAssertEqual(value["path"] as? String, "/tmp/example/project-link")
                return self.ok(["created": false, "workspace": ["workspaceId": "canonical", "path": "/tmp/example/project", "title": "Project", "sessionIds": ["older"]]])
            }
            XCTAssertEqual(value["workspaceId"] as? String, "canonical")
            XCTAssertNil(value["cwd"])
            return self.ok(["sessionId": "new"])
        }
        let workspace = try await remote.resolveWorkspace(path: "/tmp/example/project-link")
        XCTAssertEqual(workspace.sessionIds, ["older"])
        _ = try await remote.createSession(workspaceId: workspace.id, sessionId: "new")
        XCTAssertEqual(methods, ["workspace/create", "session/create"])
    }

    func testWorkspaceBaselineAndMembershipMatchDesktop() throws {
        let value: [String: Any] = ["items": [
            ["workspaceId": "first", "title": "Project", "path": "/project", "sessionIds": ["desktop-session"]],
            ["workspaceId": "default", "title": "default-workspace", "path": "/tmp/example/Documents/deepseek-harness/default-workspace", "sessionIds": []]
        ], "archivedSessionIds": ["archived"], "pinnedSessionIds": []]
        let data = try JSONSerialization.data(withJSONObject: ["type": "next", "streamId": "workspaces", "value": ["type": "baseline", "value": value]])
        let snapshot = try XCTUnwrap(WorkspaceSnapshot.decodeFrame(data))
        XCTAssertEqual(snapshot.items.map(\.id), ["first", "default"])
        XCTAssertEqual(snapshot.items[1].displayName, "默认工作区")
        XCTAssertEqual(snapshot.archivedSessionIds, ["archived"])
        XCTAssertEqual(snapshot.preferredWorkspace(sessionId: "desktop-session", savedId: "default")?.id, "first")
        XCTAssertEqual(snapshot.preferredWorkspace(sessionId: "ungrouped", savedId: "default")?.id, "default")
        XCTAssertEqual(snapshot.preferredWorkspace(sessionId: nil, savedId: "deleted")?.id, "first")
        XCTAssertFalse(snapshot.items.contains { $0.sessionIds.contains("ungrouped") }, "Matching cwd does not imply desktop membership")
    }

    func testWorkspaceDecoderDoesNotTreatReadyOrFailuresAsEmptyList() throws {
        XCTAssertNil(try WorkspaceSnapshot.decodeFrame(Data(#"{"type":"ready","clientId":"test"}"#.utf8)))
        XCTAssertThrowsError(try WorkspaceSnapshot.decodeFrame(Data(#"{"type":"error","error":{"message":"Access denied"}}"#.utf8)))
        XCTAssertThrowsError(try WorkspaceSnapshot.decodeFrame(Data(#"{"type":"next","value":{"type":"baseline","value":{}}}"#.utf8)))
    }

    func testWorkspaceInstructionsStayHiddenInSnapshotLiveEventsAndHistory() async throws {
        func instructions(_ seq: Int) -> [String: Any] {
            ["type": "user/message", "seq": seq, "surfaceOp": "append", "data": [
                "role": "user", "source": ["kind": "agent-instructions", "form": "instructions", "baseline": true],
                "content": [["type": "text", "text": "<system-reminder>\nInstructions from: AGENTS.md\nprivate workspace rules\n</system-reminder>"]],
            ]]
        }
        let remote = client { _ in
            self.ok(["records": [self.message(2, "user", text: "earlier question"), instructions(3)], "hasMore": false])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream, cursor: 20, records: [message(9, "user", text: "你好"), instructions(10), message(20)], hasMore: true)
        XCTAssertEqual(stream.messages.map(\.seq), [9, 20])
        try frame(["type": "event", "event": instructions(21)], into: stream)
        try frame(["type": "event", "event": message(22, "user", text: "<system-reminder> text I actually sent")], into: stream)
        XCTAssertEqual(stream.messages.map(\.seq), [9, 20, 22])
        await stream.loadMore()
        XCTAssertEqual(stream.messages.map(\.seq), [2, 9, 20, 22])
        XCTAssertEqual(stream.messages.last?.text, "<system-reminder> text I actually sent")
        XCTAssertFalse(stream.hasMoreHistory)
    }

    func testServerValidationAndWebSocketPath() {
        for raw in ["ftp://example.com", "file:///tmp/a", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com/#x", "example.com"] {
            XCTAssertNil(AppConfig.validatedServerURL(raw), raw)
        }
        let url = AppConfig.validatedServerURL("  https://example.com/dsh/// \n")!
        XCTAssertEqual(url.absoluteString, "https://example.com/dsh")
        XCTAssertEqual(AppConfig.webSocketURL(for: url).absoluteString, "wss://example.com/dsh/api/remote.mux")
        XCTAssertTrue(AppConfig.accessHeaders(for: url).isEmpty)
        XCTAssertTrue(AppConfig.accessHeaders(for: URL(string: "http://dsh.example.com")!).isEmpty)
    }

    func testMessageEnvelopesAndCompactAssistantText() {
        let event = message(8)
        XCTAssertEqual(EventParser.message(from: EventParser.event(from: ["type": "event", "event": event])!, fallbackSeq: 0)?.id, "s8-a")
        XCTAssertEqual(EventParser.streamText([
            ["type": "text-chunks", "texts": ["a", "b"]],
            ["type": "reasoning-chunks", "texts": ["hidden"]],
            ["type": "chunk", "chunk": ["type": "text-delta", "text": "c"]],
        ]), "abc")
    }

    func testQuestionAnswersValidateWholeFormAndCustomText() {
        let single = UserQuestion(id: "q", header: nil, question: "choose", options: ["A", "B"], multiSelect: false)
        XCTAssertFalse(QuestionAnswer(id: "q").isComplete(for: single))
        XCTAssertFalse(QuestionAnswer(id: "q", selected: ["A", "B"]).isComplete(for: single))
        XCTAssertFalse(QuestionAnswer(id: "q", selected: ["C"]).isComplete(for: single))
        XCTAssertTrue(QuestionAnswer(id: "q", custom: "typed").isComplete(for: single))
        let multi = UserQuestion(id: "m", header: nil, question: "choose", options: ["A", "B"], multiSelect: true)
        XCTAssertTrue(QuestionAnswer(id: "m", selected: ["A", "B"]).isComplete(for: multi))
        XCTAssertEqual(QuestionAnswer(id: "m", custom: " text ").payload["custom"] as? String, "text")
    }

    func testSnapshotRestoresLiveTextAndRunning() throws {
        let stream = ChatStream(sessionId: "mine", cache: nil)
        try frame(["type": "snapshot", "cursor": 10, "records": [["type": "turn/end", "seq": 9]],
                   "assistantStream": ["revision": 3, "activeAttempt": ["attemptId": "a", "nextIndex": 2,
                       "stream": [["type": "text-chunks", "texts": ["hel", "lo"]]]]]], into: stream)
        XCTAssertTrue(stream.running)
        XCTAssertEqual(stream.liveText, "hello")
        try frame(["type": "assistant-stream", "frame": ["type": "chunk", "revision": 4, "attemptId": "a", "index": 2,
            "chunk": ["type": "text-delta", "text": "!"]]], into: stream)
        XCTAssertEqual(stream.liveText, "hello!")
        try frame(["type": "event", "event": message(11)], into: stream)
        XCTAssertEqual(stream.liveText, "")
        try frame(["type": "event", "event": ["type": "turn/end", "seq": 12]], into: stream)
        XCTAssertFalse(stream.running)
    }

    func testDuplicateEventsAndReconnectKeepLoadedHistory() throws {
        let stream = ChatStream(sessionId: "mine", cache: nil)
        try snapshot(stream, records: [message(1), message(10)], hasMore: true)
        try frame(["type": "event", "event": message(10)], into: stream)
        XCTAssertEqual(stream.messages.count, 2)
        try frame(["type": "snapshot", "cursor": 11, "records": [message(10), message(11)], "hasMore": true], into: stream)
        XCTAssertEqual(stream.messages.map(\.seq), [1, 10, 11])
    }

    func testPaginationUsesSnapshotCursorAndRawRecordBoundary() async throws {
        var calls = 0
        let remote = client { request in
            calls += 1
            let root = try self.body(request)
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            let page = args["request"] as! [String: Any]
            XCTAssertEqual(page["throughSeq"] as? Int, 200)
            XCTAssertEqual(page["beforeSeq"] as? Int, calls == 1 ? 100 : 99)
            let records: [[String: Any]] = calls == 1 ? [["type": "turn/start", "seq": 99]] : [self.message(90)]
            return self.ok(["records": records, "hasMore": calls == 1])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream, cursor: 200, records: [["type": "turn/start", "seq": 100], message(105)], hasMore: true)
        try frame(["type": "event", "event": message(201)], into: stream)
        await stream.loadMore()
        XCTAssertTrue(stream.hasMoreHistory)
        await stream.loadMore()
        XCTAssertEqual(stream.messages.map(\.seq), [90, 105, 201])
        XCTAssertFalse(stream.hasMoreHistory)
    }

    func testApprovalFilteringAndTargetedCancellation() async throws {
        let remote = client { _ in self.ok() }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream)
        try approval(stream, id: "foreign", agent: "other")
        XCTAssertNil(stream.pendingApproval)
        try approval(stream, id: "a")
        try approval(stream, id: "b")
        try approval(stream, id: "a")
        try frame(["type": "cancel", "eventId": "unrelated"], into: stream)
        XCTAssertEqual(stream.pendingApproval?.id, "a")
        try frame(["type": "cancel", "eventId": "a"], into: stream)
        XCTAssertEqual(stream.pendingApproval?.id, "b")
        // Let the pass-through RPC settle before the next test replaces its stub.
        try await Task.sleep(for: .milliseconds(50))
    }

    func testFailedApprovalRemainsRetryableAndCannotDoubleSubmit() async throws {
        var calls = 0
        let remote = client { _ in
            calls += 1
            return calls == 1 ? (503, [:]) : self.ok()
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream)
        try approval(stream, id: "a")
        stream.answerApproval(allow: true)
        stream.answerApproval(allow: true)
        try await settle { !stream.answeringApproval }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(stream.pendingApproval?.id, "a")
        XCTAssertNotNil(stream.errorText)
        stream.answerApproval(allow: true)
        try await settle { stream.pendingApproval == nil }
        XCTAssertEqual(calls, 2)
    }

    func testFailedPromptAndModelDoNotInventSuccess() async throws {
        let stream = ChatStream(sessionId: "mine", client: client { _ in (503, [:]) }, cache: nil)
        try snapshot(stream)
        let sent = await stream.submitPrompt("test")
        XCTAssertFalse(sent)
        XCTAssertFalse(stream.running)
        await stream.selectModel(provider: "p", model: "new", effort: nil)
        XCTAssertEqual(stream.sessionModel, "")
        XCTAssertNotNil(stream.errorText)
    }

    func testCommandSuggestionsOnlyMatchTheCommandNameBeforeArguments() {
        XCTAssertEqual(SlashCommand.suggestionQuery(in: "/"), "")
        XCTAssertEqual(SlashCommand.suggestionQuery(in: "  /Com"), "com")
        for line in ["hello", "/compact ", "/permission read-only", "/tmp/file.txt", "//server", "`/compact`", "/compact\n"] {
            XCTAssertNil(SlashCommand.suggestionQuery(in: line), line)
        }
    }

    func testCommandCatalogIsSessionScopedAndReadsNativeArray() async throws {
        var calls = 0
        let remote = client { request in
            calls += 1
            XCTAssertEqual(request.url?.host, "catalog.example.com")
            let root = try self.body(request)
            XCTAssertEqual(root["method"] as? String, "commands/list")
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            XCTAssertEqual(args["agentId"] as? String, "mine")
            return self.ok([
                ["name": "permission", "description": "Set permissions", "input": ["hint": "preset"]],
                ["name": "compact", "description": "Compact history"],
                ["name": "compact", "description": "Duplicate"],
                ["name": "../bad", "description": "Invalid"],
            ])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, baseURL: URL(string: "https://catalog.example.com")!, cache: nil)
        await stream.loadCommands()
        await stream.loadCommands()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(stream.commands.map(\.name), ["compact", "permission"])
        XCTAssertEqual(stream.commands.last?.input?.hint, "preset")
        XCTAssertNil(stream.commandsError)
        await stream.loadCommands(force: true)
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(stream.running)
    }

    func testCommandCatalogFailureCanRetryWithoutChangingChatError() async throws {
        var calls = 0
        let stream = ChatStream(sessionId: "mine", client: client { _ in
            calls += 1
            return calls == 1 ? self.ok(["unexpected": "object"]) : self.ok([])
        }, cache: nil)
        await stream.loadCommands()
        XCTAssertNotNil(stream.commandsError)
        XCTAssertFalse(stream.loadingCommands)
        XCTAssertNil(stream.errorText)
        await stream.loadCommands()
        XCTAssertEqual(calls, 2)
        XCTAssertNil(stream.commandsError)
    }

    func testSlashCommandUsesNativeExecutorWithoutSendingPromptOrInventingModelActivity() async throws {
        var methods: [String] = []
        let remote = client { request in
            let root = try self.body(request)
            let method = root["method"] as! String
            methods.append(method)
            if method == "session/list" { return self.ok(["items": []]) }
            XCTAssertEqual(method, "commands/execute")
            XCTAssertEqual(request.timeoutInterval, 180)
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            XCTAssertEqual(args["agentId"] as? String, "mine")
            XCTAssertEqual(args["line"] as? String, "/compact")
            XCTAssertEqual((args["submittedAttachments"] as? [Any])?.count, 0)
            return self.ok(["commandId": "test-command", "result": ["kind": "success", "text": "No compactable history yet."]])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream, cursor: 0)
        let sent = await stream.submitPrompt("  /compact \n")
        XCTAssertTrue(sent)
        XCTAssertFalse(methods.contains("session/prompt"))
        XCTAssertFalse(stream.running)
        XCTAssertFalse(stream.executingCommand)
        XCTAssertNil(stream.errorText)
    }

    func testRejectedOrUnknownCommandReturnsFailureWithoutModelFallback() async throws {
        for value: [String: Any] in [["result": ["kind": "error", "text": "Agent is busy"]], [:]] {
            var calls = 0
            let remote = client { request in
                calls += 1
                XCTAssertEqual(try self.body(request)["method"] as? String, "commands/execute")
                return self.ok(value)
            }
            let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
            try snapshot(stream, cursor: 0)
            let sent = await stream.submitPrompt("/compact")
            XCTAssertFalse(sent, "The composer must retain the draft on failure")
            XCTAssertEqual(calls, 1)
            XCTAssertFalse(stream.running)
            XCTAssertFalse(stream.executingCommand)
            XCTAssertNotNil(stream.errorText)
        }
    }

    func testSlashGrammarPreservesPathsAndQuotedCommandsAsOrdinaryText() async throws {
        for line in ["/tmp/example.txt", "//host/share", "Explain /compact", "`/compact`", "/Users"] {
            XCTAssertNil(SlashCommand.name(in: line))
            let stream = ChatStream(sessionId: "mine", client: client { request in
                XCTAssertEqual(try self.body(request)["method"] as? String, "session/prompt")
                return self.ok(["accepted": true])
            }, cache: nil)
            try snapshot(stream, cursor: 0)
            let sent = await stream.submitPrompt(line)
            XCTAssertTrue(sent)
        }
        XCTAssertEqual(SlashCommand.name(in: "/permission read-only"), "permission")
        XCTAssertEqual(SlashCommand.name(in: "/compact\nextra"), "compact")
    }

    func testPermissionChangesCurrentSessionWithoutMutatingGlobalSettings() async throws {
        let remote = client { request in
            let root = try self.body(request)
            XCTAssertEqual(root["method"] as? String, "commands/execute")
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            XCTAssertEqual(args["agentId"] as? String, "mine")
            XCTAssertEqual(args["line"] as? String, "/permission read-only")
            return self.ok(["commandId": "id", "result": ["kind": "success"]])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        await stream.setPermission("read-only")
        XCTAssertEqual(stream.sessionPermission, "read-only")
    }

    func testRejectedPermissionDoesNotUpdateUI() async {
        let remote = client { _ in self.ok(["result": ["kind": "error", "text": "locked"]]) }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        await stream.setPermission("danger-full-access")
        XCTAssertNil(stream.sessionPermission)
        XCTAssertEqual(stream.errorText, "locked")
    }
    func testQuestionFormRequiresEveryAnswerAndKeepsFailedSubmission() async throws {
        var calls = 0
        let remote = client { request in
            calls += 1
            let args = (try self.body(request)["payload"] as! [String: Any])["args"] as! [String: Any]
            let outcome = args["outcome"] as! [String: Any]
            let answers = (outcome["value"] as! [String: Any])["answers"] as! [[String: Any]]
            XCTAssertEqual(answers.count, 2)
            XCTAssertEqual(answers[1]["custom"] as? String, "custom reply")
            return (503, [:])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        try snapshot(stream)
        try frame(["type": "waterfall", "event": "user-questions/request", "agentId": "mine", "eventId": "questions",
                   "request": ["questions": [
                    ["id": "one", "question": "single", "options": [["label": "A"], ["label": "B"]]],
                    ["id": "two", "question": "text"],
                   ]]], into: stream)
        stream.answerQuestions([QuestionAnswer(id: "one", selected: ["A"])])
        XCTAssertFalse(stream.answeringQuestions)
        XCTAssertEqual(calls, 0)
        stream.answerQuestions([QuestionAnswer(id: "one", selected: ["A"]), QuestionAnswer(id: "two", custom: "custom reply")])
        try await settle { !stream.answeringQuestions }
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(stream.pendingQuestions)
        XCTAssertNotNil(stream.errorText)
    }

    func testMalformedRPCResultIsNotAcceptedAsSuccess() async {
        let remote = client { _ in (200, ["result": ["value": [:]]]) }
        do {
            try await remote.cancel(sessionId: "mine")
            XCTFail("Missing ok must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("响应")) }
    }

    func testStatusEventsOnlyUpdateTheirOwnSession() throws {
        let stream = ChatStream(sessionId: "mine", cache: nil)
        try snapshot(stream)
        try frame(["type": "emit", "event": "api-session/status", "args": ["other", true]], into: stream)
        XCTAssertFalse(stream.running)
        try frame(["type": "emit", "event": "api-session/status", "args": ["mine", true]], into: stream)
        XCTAssertTrue(stream.running)
        stream.disconnect()
        XCTAssertFalse(stream.connected)
        XCTAssertFalse(stream.reconnecting)
    }

    func testMarkdownRendersHeadingsListsQuotesAndTables() {
        let text = "# Title\n\n- **bold**\n2. second\n> quote\n\n| A | B |\n| --- | :---: |\n| one | two |\n\n---"
        let blocks = MarkdownBlock.parse(text).map(\.content)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"), .listItem(marker: "•", text: "**bold**", indent: 0),
            .listItem(marker: "2.", text: "second", indent: 0), .quote("quote"),
            .table(headers: ["A", "B"], rows: [["one", "two"]]), .divider,
        ])
    }

    func testMarkdownKeepsUnfinishedCodeAndBlankLines() {
        XCTAssertEqual(MarkdownBlock.parse("```swift\n\nlet x = 1\n\n").first?.content,
                       .code(language: "swift", text: "\nlet x = 1\n\n"))
        XCTAssertEqual(MarkdownBlock.parse("~~~sh\necho hi\n~~~\nafter").map(\.content),
                       [.code(language: "sh", text: "echo hi"), .paragraph("after")])
    }

    func testMarkdownTableHandlesEscapedPipesAndInlineCode() {
        let text = "| A | B |\n| --- | --- |\n| a\\|b | `x|y` |"
        XCTAssertEqual(MarkdownBlock.parse(text).first?.content,
                       .table(headers: ["A", "B"], rows: [["a|b", "`x|y`"]]))
    }

}
