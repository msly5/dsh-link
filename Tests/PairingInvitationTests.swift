import Foundation
import XCTest
@testable import DSHRemoteCore

final class PairingInvitationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func link(_ changes: [String: Any] = [:]) throws -> String {
        var payload: [String: Any] = ["version": 1, "expires_at": now.timeIntervalSince1970 + 300,
            "server_url": "https://example.com/dsh", "client_id": "test-client-id", "client_secret": "test-client-secret"]
        payload.merge(changes) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return "dshremote://configure?data=" + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func testImportsTheExactMacGeneratedFixtureWithoutSavingCredentials() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("bridge/test/fixtures/pairing-v1.json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let before = AppConfig.profile
        let invitation = try PairingInvitation(scannedValue: try XCTUnwrap(fixture["link"] as? String), now: now)
        XCTAssertEqual(invitation.profile.serverURL.absoluteString, "https://example.com/dsh")
        XCTAssertEqual(invitation.profile.clientID, "test-client-id")
        XCTAssertEqual(invitation.profile.clientSecret, "test-client-secret")
        XCTAssertEqual(invitation.expiresAt.timeIntervalSince(now), 300)
        XCTAssertEqual(AppConfig.profile, before)
    }
    func testRejectsExpiredFutureUnsupportedAndInvalidProfiles() throws {
        for changes: [String: Any] in [["expires_at": now.timeIntervalSince1970], ["expires_at": now.timeIntervalSince1970 + 361],
            ["version": 2], ["server_url": "http://example.com"], ["server_url": "https://user:pass@example.com"],
            ["server_url": "https://example.com?x=1"], ["client_secret": "test\ninjected"], ["client_id": ""]] {
            XCTAssertThrowsError(try PairingInvitation(scannedValue: link(changes), now: now))
        }
    }
    func testRejectsOtherQRLinksDuplicateQueriesAndOversizedData() throws {
        let valid = try link()
        for value in ["https://example.com", "dshremote://configure?data=invalid", valid + "&data=other",
            valid + "#fragment", valid.replacingOccurrences(of: "configure?", with: "configure/path?"),
            valid.replacingOccurrences(of: "configure", with: "session"), String(repeating: "x", count: 2001)] {
            XCTAssertThrowsError(try PairingInvitation(scannedValue: value, now: now))
        }
    }
}
