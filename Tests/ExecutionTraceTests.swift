import Foundation
import XCTest
@testable import DSHRemoteCore

@MainActor
final class ExecutionTraceTests: XCTestCase {
    private func call(_ seq: Int, id: String = "a", name: String = "bash") -> [String: Any] {
        ["type": "tool/call", "seq": seq, "data": ["callId": id, "name": name,
            "arguments": #"{"description":"Check build output","command":"swift build"}"#]]
    }

    private func result(_ seq: Int, id: String = "a", failed: Bool = false) -> [String: Any] {
        ["type": "tool/result", "seq": seq, "data": ["message": [
            "source": ["kind": "tool", "callId": id], "isError": failed,
            "content": [["type": "text", "text": failed ? "build failed" : "build succeeded"]],
        ]]]
    }

    private func send(_ frame: [String: Any], to stream: ChatStream) throws {
        stream.handle(String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self))
    }

    func testSnapshotShowsReasoningAndMatchesResultsToNamedCalls() throws {
        let stream = ChatStream(sessionId: "test", cache: nil)
        let assistant: [String: Any] = ["type": "assistant/message", "seq": 1, "data": ["message": ["content": [
            ["type": "reasoning", "text": "Check the build before continuing."],
            ["type": "tool-call", "id": "a", "name": "bash", "arguments": "{}"],
        ]]]]
        try send(["type": "snapshot", "cursor": 3, "records": [assistant, call(2), result(3)]], to: stream)
        XCTAssertEqual(stream.messages.count, 2, "The tool-call block and the executed call must not create duplicate rows")
        XCTAssertEqual(stream.messages[0].activity?.kind, .reasoning)
        let command = stream.messages[1]
        XCTAssertEqual(command.seq, 2)
        XCTAssertEqual(command.activity?.title, "运行命令")
        XCTAssertEqual(command.activity?.summary, "Check build output")
        XCTAssertEqual(command.activity?.input, "swift build")
        XCTAssertEqual(command.activity?.phase, .completed)
        XCTAssertEqual(command.text, "build succeeded")
    }

    func testLiveParallelResultsKeepCallOrderAndFailureStatus() throws {
        let stream = ChatStream(sessionId: "test", cache: nil)
        try send(["type": "snapshot", "cursor": 0, "records": []], to: stream)
        for event in [call(1), call(2, id: "b"), result(3, id: "b")] {
            try send(["type": "event", "event": event], to: stream)
        }
        XCTAssertEqual(stream.messages.map(\.id), ["call:a", "call:b"])
        XCTAssertEqual(stream.messages.map { $0.activity?.phase }, [.running, .completed])
        try send(["type": "event", "event": result(4, failed: true)], to: stream)
        XCTAssertEqual(stream.messages.map(\.seq), [1, 2])
        XCTAssertEqual(stream.messages[0].activity?.phase, .failed)
        XCTAssertEqual(stream.messages[0].text, "build failed")
        try send(["type": "event", "event": result(4, failed: true)], to: stream)
        XCTAssertEqual(stream.messages.count, 2)
    }

    func testEarlierCallEnrichesAlreadyLoadedResultWithoutLosingOutput() async throws {
        StubProtocol.handler = { _ in (200, ["result": ["ok": true, "value": ["records": [self.call(10)], "hasMore": false]]]) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let stream = ChatStream(sessionId: "test", client: RemoteClient(session: URLSession(configuration: configuration)), cache: nil)
        try send(["type": "snapshot", "cursor": 20, "records": [result(20)], "hasMore": true], to: stream)
        await stream.loadMore()
        XCTAssertEqual(stream.messages.count, 1)
        XCTAssertEqual(stream.messages[0].seq, 10)
        XCTAssertEqual(stream.messages[0].activity?.summary, "Check build output")
        XCTAssertEqual(stream.messages[0].activity?.phase, .completed)
        XCTAssertEqual(stream.messages[0].text, "build succeeded")
    }

    func testLiveReasoningRestoresAndBecomesOneCompletedRow() throws {
        let stream = ChatStream(sessionId: "test", cache: nil)
        try send(["type": "snapshot", "cursor": 0, "records": [], "assistantStream": ["revision": 1,
            "activeAttempt": ["attemptId": "attempt", "nextIndex": 1,
                              "stream": [["type": "reasoning-chunks", "texts": ["Checking "]]]]]], to: stream)
        XCTAssertEqual(stream.liveReasoning, "Checking ")
        XCTAssertEqual(stream.timelineMessages.last?.activity?.phase, .running)
        try send(["type": "assistant-stream", "frame": ["type": "chunk", "revision": 2, "attemptId": "attempt", "index": 1,
            "chunk": ["type": "reasoning-delta", "text": "the build."]]], to: stream)
        XCTAssertEqual(stream.liveReasoning, "Checking the build.")
        let complete: [String: Any] = ["type": "assistant/message", "seq": 1, "data": ["message": ["content": [
            ["type": "reasoning", "text": "Checking the build."], ["type": "text", "text": "Done."],
        ]]]]
        try send(["type": "event", "event": complete], to: stream)
        XCTAssertTrue(stream.liveReasoning.isEmpty)
        XCTAssertEqual(stream.timelineMessages.count, 2)
        XCTAssertEqual(stream.timelineMessages[0].activity?.kind, .reasoning)
        XCTAssertEqual(stream.timelineMessages[1].role, .assistant)
        XCTAssertEqual(stream.timelineMessages[1].text, "Done.")
    }

    func testDesktopLabelsUseActualArgumentsAndMalformedArgumentsRemainReadable() {
        let kill = ExecutionActivity(kind: .tool, name: "job_kill", arguments: #"{"job_id":"bash-test"}"#, phase: .completed)
        XCTAssertEqual(kill.title, "取消后台任务")
        XCTAssertEqual(kill.summary, "bash-test")
        XCTAssertEqual(kill.summary(output: "requested cancellation of job bash-test"), "bash-test · 已请求取消")
        let malformed = ExecutionActivity(kind: .tool, name: "custom_tool", arguments: "incomplete {", phase: .running)
        XCTAssertEqual(malformed.title, "custom_tool")
        XCTAssertEqual(malformed.input, "incomplete {")
    }

    func testCommandExitMarkersDistinguishProcessFailureFromSuccessfulToolTransport() {
        let command = ExecutionActivity(kind: .tool, name: "bash", phase: .completed)
        XCTAssertEqual(command.settledPhase(output: "compile error\n[exit code: 1]"), .failed)
        XCTAssertEqual(command.settledPhase(output: "ok\n[exit code: 0]"), .completed)
        XCTAssertEqual(command.settledPhase(output: "still running in background"), .completed)
        let other = ExecutionActivity(kind: .tool, name: "read", phase: .completed)
        XCTAssertEqual(other.settledPhase(output: "[exit code: 1]"), .completed)
    }
}
