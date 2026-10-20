import Foundation
import XCTest
@testable import DSHRemoteCore

@MainActor
final class ConversationCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: ConversationCache!
    private let server = URL(string: "https://one.example/dsh")!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "DSH-cache-tests-" + UUID().uuidString)
        cache = ConversationCache(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        cache = nil
    }

    private func message(_ seq: Int, text: String = "saved") -> ChatMessage {
        ChatMessage(id: "s\(seq)-a", seq: seq, role: .assistant, text: text)
    }

    private func snapshot(_ stream: ChatStream, cursor: Int, records: [[String: Any]], hasMore: Bool = false) throws {
        let frame: [String: Any] = ["type": "snapshot", "cursor": cursor, "records": records, "hasMore": hasMore]
        stream.handle(String(decoding: try JSONSerialization.data(withJSONObject: frame), as: UTF8.self))
    }

    private func record(_ seq: Int, text: String = "live") -> [String: Any] {
        ["type": "assistant/message", "seq": seq, "data": ["message": ["content": [["type": "text", "text": text]]]]]
    }

    func testDiskCacheSurvivesNewStoreAndSeparatesServersPathsAndSessions() async throws {
        await cache.save(server: server, sessionId: "same", cursor: 10, oldestSeq: 1, messages: [message(1)])
        let reopened = ConversationCache(directory: directory)
        let restored = await reopened.load(server: server, sessionId: "same")
        XCTAssertEqual(restored?.messages, [message(1)])
        for other in ["https://two.example/dsh", "https://one.example/other", "http://one.example/dsh", "https://one.example:8443/dsh"] {
            let value = await reopened.load(server: URL(string: other)!, sessionId: "same")
            XCTAssertNil(value)
        }
        let otherSession = await reopened.load(server: server, sessionId: "different")
        XCTAssertNil(otherSession)
        let canonical = await reopened.load(server: URL(string: "https://ONE.example:443/dsh/")!, sessionId: "same")
        XCTAssertEqual(canonical?.messages, [message(1)])
    }

    func testCacheRestoresMessagesWithoutRestoringConnectionOrPendingActions() async throws {
        await cache.save(server: server, sessionId: "mine", cursor: 10, oldestSeq: 1,
                         messages: [message(1), message(10, text: "cached")])
        let stream = ChatStream(sessionId: "mine", baseURL: server, cache: cache)
        await stream.restoreCachedMessages()
        XCTAssertEqual(stream.messages.map(\.seq), [1, 10])
        XCTAssertTrue(stream.showingCachedMessages)
        XCTAssertFalse(stream.connected)
        XCTAssertFalse(stream.hasMoreHistory)
        XCTAssertNil(stream.pendingApproval)
        XCTAssertNil(stream.pendingQuestions)
        XCTAssertEqual(stream.liveText, "")
        try snapshot(stream, cursor: 11, records: [record(10, text: "authoritative"), record(11)], hasMore: true)
        XCTAssertEqual(stream.messages.map(\.seq), [1, 10, 11])
        XCTAssertEqual(stream.messages[1].text, "authoritative")
        XCTAssertFalse(stream.showingCachedMessages)
        XCTAssertTrue(stream.connected)
        await stream.saveCachedMessages()
        let reopened = ConversationCache(directory: directory)
        let saved = await reopened.load(server: server, sessionId: "mine")
        XCTAssertEqual(saved?.messages, stream.messages)
    }

    func testLongOfflineGapResetsHistoryBoundaryInsteadOfHidingMissingMessages() async throws {
        await cache.save(server: server, sessionId: "mine", cursor: 10, oldestSeq: 1, messages: [message(1), message(10)])
        let stream = ChatStream(sessionId: "mine", baseURL: server, cache: cache)
        await stream.restoreCachedMessages()
        try snapshot(stream, cursor: 100, records: [record(90), record(100)], hasMore: true)
        XCTAssertEqual(stream.messages.map(\.seq), [90, 100])
        XCTAssertTrue(stream.hasMoreHistory)
        await stream.saveCachedMessages()
        let saved = await cache.load(server: server, sessionId: "mine")
        XCTAssertEqual(saved?.oldestSeq, 90)
    }

    func testServerRollbackAndEmptySnapshotRemoveStaleCachedContent() async throws {
        await cache.save(server: server, sessionId: "mine", cursor: 100, oldestSeq: 1, messages: [message(1), message(100)])
        let stream = ChatStream(sessionId: "mine", baseURL: server, cache: cache)
        await stream.restoreCachedMessages()
        try snapshot(stream, cursor: 5, records: [record(5, text: "reset")])
        XCTAssertEqual(stream.messages.map(\.seq), [5])
        try snapshot(stream, cursor: 0, records: [])
        XCTAssertTrue(stream.messages.isEmpty)
        await stream.saveCachedMessages()
        let saved = await cache.load(server: server, sessionId: "mine")
        XCTAssertEqual(saved?.messages, [])
    }

    func testCompleteServerSnapshotRemovesOlderCachedMessages() async throws {
        await cache.save(server: server, sessionId: "mine", cursor: 10, oldestSeq: 1, messages: [message(1), message(10)])
        let stream = ChatStream(sessionId: "mine", baseURL: server, cache: cache)
        await stream.restoreCachedMessages()
        try snapshot(stream, cursor: 11, records: [record(10), record(11)], hasMore: false)
        XCTAssertEqual(stream.messages.map(\.seq), [10, 11])
        XCTAssertFalse(stream.hasMoreHistory)
        await stream.saveCachedMessages()
    }

    func testCacheBoundsHistoryAndIgnoresLateOlderWrites() async throws {
        let count = ConversationCache.messageLimit + 5
        let now = Date()
        await cache.save(server: server, sessionId: "mine", cursor: count, oldestSeq: 0,
                         messages: (0..<count).map { message($0) }, recordedAt: now)
        await cache.save(server: server, sessionId: "mine", cursor: 1, oldestSeq: 0,
                         messages: [message(0, text: "late")], recordedAt: now.addingTimeInterval(-1))
        let saved = await cache.load(server: server, sessionId: "mine")
        XCTAssertEqual(saved?.messages.count, ConversationCache.messageLimit)
        XCTAssertEqual(saved?.oldestSeq, 5)
        XCTAssertEqual(saved?.cursor, count)
    }

    func testLeavingChatImmediatelyStillSavesLastSnapshot() async throws {
        var stream: ChatStream? = ChatStream(sessionId: "mine", baseURL: server, cache: cache)
        try snapshot(stream!, cursor: 10, records: [record(10, text: "last message")])
        stream?.disconnect()
        stream = nil
        var saved: ConversationCache.Snapshot?
        for _ in 0..<100 {
            saved = await cache.load(server: server, sessionId: "mine")
            if saved != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(saved?.messages.first?.text, "last message")
    }

    func testOldDisplayCacheIsRebuiltWithoutGuessingFromUserText() async throws {
        let quote = ChatMessage(id: "s1-u", seq: 1, role: .user, text: "<system-reminder> user quote")
        await cache.save(server: server, sessionId: "mine", cursor: 2, oldestSeq: 1, messages: [quote])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        old["version"] = 1
        try JSONSerialization.data(withJSONObject: old).write(to: file)
        let reopened = ConversationCache(directory: directory)
        let stale = await reopened.load(server: server, sessionId: "mine")
        XCTAssertNil(stale, "v1 lacks source metadata, so it cannot safely distinguish internal instructions from user quotes")
        await reopened.save(server: server, sessionId: "mine", cursor: 2, oldestSeq: 1, messages: [quote])
        let refreshed = await reopened.load(server: server, sessionId: "mine")
        XCTAssertEqual(refreshed?.version, 3)
        XCTAssertEqual(refreshed?.messages, [quote], "Never remove real user text based on reminder tags")
    }

    func testExecutionMetadataSurvivesRestartAndPendingCallsStayLiveOnly() async throws {
        let pending = ChatMessage(id: "call:pending", seq: 2, role: .tool, text: "",
                                  activity: ExecutionActivity(kind: .tool, name: "bash", arguments: "{}", phase: .running))
        let complete = ChatMessage(id: "call:done", seq: 3, role: .tool, text: "result",
                                   activity: ExecutionActivity(kind: .tool, name: "bash", arguments: #"{"description":"Build"}"#, phase: .completed))
        await cache.save(server: server, sessionId: "mine", cursor: 4, oldestSeq: 1, messages: [message(1), pending, complete])
        let reopened = ConversationCache(directory: directory)
        let saved = await reopened.load(server: server, sessionId: "mine")
        XCTAssertEqual(saved?.messages.map(\.id), ["s1-a", "call:done"])
        XCTAssertEqual(saved?.messages.last?.activity?.summary, "Build")
        XCTAssertEqual(saved?.messages.last?.text, "result")
    }

    func testCorruptCacheFallsBackToNetworkAndIdsCannotEscapeCacheDirectory() async throws {
        let id = "../../outside"
        await cache.save(server: server, sessionId: id, cursor: 1, oldestSeq: 1, messages: [message(1)])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].pathExtension, "json")
        try Data("broken".utf8).write(to: files[0])
        let stream = ChatStream(sessionId: id, baseURL: server, cache: cache)
        await stream.restoreCachedMessages()
        XCTAssertTrue(stream.messages.isEmpty)
        XCTAssertFalse(stream.showingCachedMessages)
        XCTAssertNil(stream.errorText)
    }
}
