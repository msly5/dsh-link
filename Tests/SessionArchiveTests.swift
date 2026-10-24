import Foundation
import XCTest
@testable import DSHRemoteCore

@MainActor
final class SessionArchiveTests: XCTestCase {
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> RemoteClient {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return RemoteClient(session: URLSession(configuration: config))
    }

    private func requestValue(_ request: URLRequest) throws -> (String, [String: Any]) {
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open(); defer { stream.close() }
            var result = Data(), buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let args = try XCTUnwrap((root["payload"] as? [String: Any])?["args"] as? [String: Any])
        return (try XCTUnwrap(root["method"] as? String), try XCTUnwrap(args["request"] as? [String: Any]))
    }

    func testArchiveUsesDesktopRegistryAndDoesNotStopWorkByDefault() async throws {
        let remote = client { request in
            let (method, value) = try self.requestValue(request)
            XCTAssertEqual(method, "workspace/archiveSession")
            XCTAssertEqual(request.url?.path, "/api/workspace/archiveSession")
            XCTAssertEqual(value["sessionId"] as? String, "session-a")
            XCTAssertNil(value["stopActivity"])
            return (200, ["result": ["ok": true, "value": ["archivedSessionIds": ["older", "session-a"]]]])
        }
        let ids = try await remote.setSessionArchived("session-a", archived: true)
        XCTAssertEqual(ids, ["older", "session-a"])
    }

    func testConfirmedArchiveStopsActivityButRestoreDoesNot() async throws {
        var calls = 0
        let remote = client { request in
            calls += 1
            let (method, value) = try self.requestValue(request)
            if calls == 1 {
                XCTAssertEqual(method, "workspace/archiveSession")
                XCTAssertEqual(value["stopActivity"] as? Bool, true)
            } else {
                XCTAssertEqual(method, "workspace/unarchiveSession")
                XCTAssertNil(value["stopActivity"])
            }
            return (200, ["result": ["ok": true, "value": ["archivedSessionIds": []]]])
        }
        _ = try await remote.setSessionArchived("a", archived: true, stopActivity: true)
        _ = try await remote.setSessionArchived("a", archived: false, stopActivity: true)
        XCTAssertEqual(calls, 2)
    }

    func testActiveSessionRequiresConfirmationWithoutAutomaticRetry() async throws {
        var calls = 0
        let remote = client { _ in
            calls += 1
            return (200, ["result": ["ok": false, "error": ["code": "workspace/session-active", "message": "Session has active background work"]]])
        }
        do {
            _ = try await remote.setSessionArchived("a", archived: true)
            XCTFail("Active work must not be archived implicitly")
        } catch let error as RemoteError {
            XCTAssertEqual(error.code, "workspace/session-active")
        }
        XCTAssertEqual(calls, 1)
    }

    func testMissingArchiveSetIsNotTreatedAsSuccess() async throws {
        let remote = client { _ in (200, ["result": ["ok": true, "value": [:]]]) }
        do {
            _ = try await remote.setSessionArchived("a", archived: true)
            XCTFail("Malformed response must not remove a row locally")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
}
