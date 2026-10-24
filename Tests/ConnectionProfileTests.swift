import Foundation
import XCTest
@testable import DSHRemoteCore

final class ConnectionProfileTests: XCTestCase {
    func testNoCompiledCredentialsOrAutomaticPersonalServer() {
        XCTAssertEqual(AppConfig.defaultBaseURL.host, "unconfigured.invalid")
    }
    func testCredentialScopeIncludesSchemeHostPortAndBasePath() throws {
        let profile = try ConnectionProfile(server: " https://EXAMPLE.com:443/dsh/// ", clientID: "test-id", clientSecret: "test-secret")
        XCTAssertEqual(profile.serverURL.absoluteString, "https://example.com/dsh")
        XCTAssertEqual(profile.headers(for: URL(string: "https://example.com/dsh")!)["CF-Access-Client-Secret"], "test-secret")
        for url in ["http://example.com/dsh", "https://other.example/dsh", "https://example.com:8443/dsh", "https://example.com/elsewhere"] {
            XCTAssertTrue(profile.headers(for: URL(string: url)!).isEmpty, url)
        }
    }
    func testRejectsIncompleteCredentialsAndInsecureServer() {
        for (url, id, secret) in [("", "test", "test"), ("http://example.com", "test", "test"),
                                  ("https://example.com", " ", "test"), ("https://example.com", "test", ""),
                                  ("https://example.com", "test\nheader", "test"), ("https://user:pass@example.com", "test", "test")] {
            XCTAssertThrowsError(try ConnectionProfile(server: url, clientID: id, clientSecret: secret))
        }
    }
    func testQuickTunnelKeyUsesOnlyURLScopedBearerAuthentication() throws {
        let key = String(repeating: "a", count: 64)
        let profile = try ConnectionProfile(server: "https://fixture.trycloudflare.com", clientID: "unused", clientSecret: "unused",
                                            authMode: .quickTunnel, connectionKey: key)
        XCTAssertEqual(profile.headers(for: profile.serverURL), ["Authorization": "Bearer " + key])
        XCTAssertTrue(profile.clientID.isEmpty)
        XCTAssertTrue(profile.clientSecret.isEmpty)
        XCTAssertTrue(profile.headers(for: URL(string: "https://other.trycloudflare.com")!).isEmpty)
        XCTAssertTrue(profile.headers(for: URL(string: "http://fixture.trycloudflare.com")!).isEmpty)
        for invalid in ["", "short", String(repeating: "g", count: 64), key + "\nInjected"] {
            XCTAssertThrowsError(try ConnectionProfile(server: profile.serverURL.absoluteString, authMode: .quickTunnel, connectionKey: invalid))
        }
        let store = CredentialStore(service: "app.dshremote.test." + UUID().uuidString)
        defer { try? store.delete() }
        try store.save(profile)
        XCTAssertEqual(try store.load(), profile)
    }
    func testLegacyKeychainProfileStillDecodesAsAccess() throws {
        let data = try JSONSerialization.data(withJSONObject: ["serverURL": "https://example.com", "clientID": "test-id", "clientSecret": "test-secret"])
        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertEqual(profile.authMode, .access)
        XCTAssertEqual(profile.headers(for: profile.serverURL)["CF-Access-Client-Id"], "test-id")
        XCTAssertTrue(profile.connectionKey.isEmpty)
    }
    func testUnsavedConnectionTestUsesDraftAndDoesNotChangeSavedProfile() async throws {
        let before = AppConfig.profile
        let draft = try ConnectionProfile(server: "https://draft.example", clientID: "draft-id", clientSecret: "draft-secret")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { req in
            XCTAssertEqual(req.url?.host, "draft.example")
            XCTAssertEqual(req.value(forHTTPHeaderField: "CF-Access-Client-Id"), "draft-id")
            XCTAssertEqual(req.value(forHTTPHeaderField: "CF-Access-Client-Secret"), "draft-secret")
            return (200, ["result": ["ok": true, "value": ["items": []]]])
        }
        let client = RemoteClient(session: SecureTransport.session(configuration: config))
        _ = try await client.listSessions(baseURL: draft.serverURL, credentials: draft)
        XCTAssertEqual(AppConfig.profile, before)
    }
    func testKeychainStoresAndClearsAnIsolatedURLBoundProfile() throws {
        let store = CredentialStore(service: "app.dshremote.test." + UUID().uuidString)
        defer { try? store.delete() }
        XCTAssertNil(try store.load())
        let first = try ConnectionProfile(server: "https://first.example", clientID: "test-id", clientSecret: "test-secret")
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        let replacement = try ConnectionProfile(server: "https://second.example", clientID: "new-test-id", clientSecret: "new-test-secret")
        try store.save(replacement)
        XCTAssertEqual(try store.load(), replacement)
        try store.delete()
        XCTAssertNil(try store.load())
        try store.delete()
    }
    func testRedirectIsRejectedEvenWhenDestinationLooksSimilar() throws {
        let url = URL(string: "https://example.com/api/session/list")!
        let session = SecureTransport.session()
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        defer { task.cancel() }
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        SecureTransport().urlSession(session, task: task, willPerformHTTPRedirection: response,
                                     newRequest: URLRequest(url: URL(string: "https://evil.example")!)) { request in
            XCTAssertNil(request)
        }
    }
}
