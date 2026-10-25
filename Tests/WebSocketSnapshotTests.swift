import Foundation
import Network
import XCTest
@testable import DSHRemoteCore

/// Exercises Foundation's real WebSocket buffering, which URLProtocol stubs bypass.
@MainActor
private final class SnapshotSocketServer {
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private let frame: Data
    private let endpoint: String
    private let opcode: NWProtocolWebSocket.Opcode

    init(endpoint: String, frame: [String: Any], binary: Bool = false) throws {
        self.endpoint = endpoint
        self.frame = try JSONSerialization.data(withJSONObject: frame)
        self.opcode = binary ? .binary : .text
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.listener.stateUpdateHandler = nil
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)")!)
                    case .failed(let error):
                        self.listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        connections.forEach { $0.cancel() }
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, error == nil, let data,
                      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                if request["endpoint"] as? String == "$events" {
                    self.send(Data(#"{"type":"ready","clientId":"fixture-client"}"#.utf8), on: connection, opcode: .text)
                } else if request["endpoint"] as? String == self.endpoint {
                    self.send(self.frame, on: connection, opcode: self.opcode)
                }
                self.receive(connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection, opcode: NWProtocolWebSocket.Opcode) {
        let context = NWConnection.ContentContext(identifier: "snapshot", metadata: [NWProtocolWebSocket.Metadata(opcode: opcode)])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

@MainActor
final class WebSocketSnapshotTests: XCTestCase {
    func testChatConnectsAndKeepsLargeSnapshotContent() async throws {
        let text = String(repeating: "synthetic conversation data ", count: 50_000)
        XCTAssertGreaterThan(text.utf8.count, 1024 * 1024)
        let server = try SnapshotSocketServer(endpoint: "session/follow", frame: [
            "type": "next", "streamId": "follow", "value": [
                "type": "snapshot", "cursor": 1, "hasMore": false, "records": [[
                    "type": "assistant/message", "seq": 1,
                    "data": ["message": ["content": [["type": "text", "text": text]]]],
                ]],
            ],
        ])
        let url = try await server.start()
        defer { server.stop() }
        let stream = ChatStream(sessionId: "large-fixture", baseURL: url, cache: nil)
        defer { stream.disconnect() }
        stream.connect()
        for _ in 0..<500 {
            if stream.connected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(stream.connected, stream.errorText ?? "Large snapshot did not arrive")
        XCTAssertNil(stream.errorText)
        XCTAssertFalse(stream.reconnecting)
        XCTAssertEqual(stream.messages.count, 1)
        XCTAssertEqual(stream.messages.first?.text.utf8.count, text.utf8.count)
    }

    func testWorkspaceSnapshotReceivesLargeBinaryFrame() async throws {
        let sessions = (0..<30_000).map { "synthetic-session-\($0)-large-workspace" }
        let server = try SnapshotSocketServer(endpoint: "workspace/follow", frame: [
            "type": "next", "streamId": "workspaces", "value": [
                "type": "baseline", "value": ["items": [[
                    "workspaceId": "fixture-workspace", "title": "Synthetic workspace", "path": "/fixture", "sessionIds": sessions,
                ]], "archivedSessionIds": []],
            ],
        ], binary: true)
        let url = try await server.start()
        defer { server.stop() }
        let snapshot = try await RemoteClient().workspaceSnapshot(baseURL: url)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.sessionIds.count, sessions.count)
        XCTAssertEqual(snapshot.items.first?.sessionIds.first, sessions.first)
        XCTAssertEqual(snapshot.items.first?.sessionIds.last, sessions.last)
    }
}
