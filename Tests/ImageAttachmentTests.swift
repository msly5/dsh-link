import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DSHRemoteCore

@MainActor
final class ImageAttachmentTests: XCTestCase {
    private func imageData(width: Int = 80, height: Int = 40, type: UTType = .png, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.0, kCGImagePropertyGPSLongitude: 121.0],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func client(_ handler: @escaping (URLRequest) throws -> (Int, [String: Any])) -> RemoteClient {
        StubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return RemoteClient(session: URLSession(configuration: configuration), credentials: try! ConnectionProfile(server: AppConfig.defaultBaseURL.absoluteString, clientID: "test-only-id", clientSecret: "test-only-secret"))
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

    func testPreparationAppliesOrientationAndStripsLocationMetadata() throws {
        let prepared = try ImagePreparation.prepare(imageData(type: .jpeg, orientation: 6))
        XCTAssertEqual(prepared.mediaType, "image/jpeg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 80)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNotEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertNotNil(ImagePreparation.thumbnail(prepared.preview, maxDimension: 240))
    }

    func testPreparationDownsizesAndRejectsInvalidBytes() throws {
        let limits = ImageLimits(maxImageBytes: 100_000, maxImagesPerMessage: 1, maxMessageImageBytes: 100_000,
                                 maxImagePixels: 10_000, maxImageDimension: 120, mediaTypes: ["image/png"])
        let image = try ImagePreparation.prepare(imageData(width: 800, height: 400), limits: limits)
        let decoded = try XCTUnwrap(ImagePreparation.thumbnail(image.data, maxDimension: 1000))
        XCTAssertLessThanOrEqual(decoded.width, 100)
        XCTAssertLessThanOrEqual(decoded.height * decoded.width, 10_000)
        XCTAssertLessThanOrEqual(image.data.count, limits.maxImageBytes)
        XCTAssertThrowsError(try ImagePreparation.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(try limits.validate([image, image]))
    }

    func testImageOnlyAndMixedPromptsUseCanonicalWireContent() async throws {
        let image = try ImagePreparation.prepare(imageData())
        var calls = 0
        let remote = client { request in
            calls += 1
            let root = try self.body(request)
            XCTAssertEqual(root["method"] as? String, "session/prompt")
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            let prompt = args["request"] as! [String: Any]
            XCTAssertEqual(prompt["sessionId"] as? String, "mine")
            let content = prompt["content"] as! [[String: Any]]
            XCTAssertEqual(content.count, calls == 1 ? 1 : 2)
            let uploaded = content.last!
            XCTAssertEqual(uploaded["type"] as? String, "image")
            XCTAssertEqual(uploaded["mediaType"] as? String, image.mediaType)
            XCTAssertEqual(Data(base64Encoded: uploaded["data"] as! String), image.data)
            if calls == 2 { XCTAssertEqual(content.first?["text"] as? String, "describe") }
            return (200, ["result": ["ok": true, "value": ["accepted": true]]])
        }
        try await remote.prompt(sessionId: "mine", text: "", images: [image])
        try await remote.prompt(sessionId: "mine", text: "describe", images: [image])
        XCTAssertEqual(calls, 2)
    }

    func testImageOnlyHistoryIsVisibleAndOldTextCachesStillDecode() throws {
        let event: [String: Any] = ["type": "user/message", "seq": 9, "data": ["content": [[
            "type": "image", "attachment": ["attachmentId": "sha256:test", "mediaType": "image/png", "name": "test.png"],
        ]]]]
        let message = try XCTUnwrap(EventParser.message(from: event, fallbackSeq: 0))
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.text, "")
        XCTAssertEqual(message.images.first?.attachmentId, "sha256:test")
        let roundTrip = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(roundTrip, message)
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":"s1-u","seq":1,"role":"user","text":"old"}"#.utf8))
        XCTAssertEqual(old.images, [])
        XCTAssertEqual(old.text, "old")
    }

    func testUnsupportedModelReturnsFailureAndDoesNotInventMessage() async throws {
        let remote = client { _ in
            (200, ["result": ["ok": false, "error": ["message": "Model test does not support image input."]]])
        }
        let stream = ChatStream(sessionId: "mine", client: remote, cache: nil)
        stream.handle(#"{"type":"snapshot","cursor":0,"records":[]}"#)
        let success = await stream.submitPrompt("", images: [try ImagePreparation.prepare(imageData())])
        XCTAssertFalse(success)
        XCTAssertTrue(stream.messages.isEmpty)
        XCTAssertTrue(stream.errorText?.contains("当前模型不支持图片") == true)
    }

    func testImageReadsAreAuthenticatedScopedAndDiskCached() async throws {
        let bytes = try imageData()
        let directory = FileManager.default.temporaryDirectory.appending(path: "DSH-image-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = ChatImage(attachmentId: "sha256:test", mediaType: "image/png", name: nil)
        var calls = 0
        let remote = client { request in
            calls += 1
            let root = try self.body(request)
            XCTAssertEqual(root["method"] as? String, "session/attachment")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "CF-Access-Client-Id"))
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            XCTAssertNotNil((args["request"] as? [String: Any])?["sessionId"])
            return (200, ["result": ["ok": true, "value": ["attachment": ["attachmentId": image.attachmentId], "data": bytes.base64EncodedString()]]])
        }
        let store = ImageAttachmentStore(directory: directory)
        let first = try await store.data(server: AppConfig.defaultBaseURL, sessionId: "one", image: image, client: remote)
        XCTAssertEqual(first, bytes)
        let reopened = ImageAttachmentStore(directory: directory)
        let cached = try await reopened.data(server: AppConfig.defaultBaseURL, sessionId: "one", image: image, client: remote)
        XCTAssertEqual(cached, bytes)
        XCTAssertEqual(calls, 1)
        _ = try await reopened.data(server: AppConfig.defaultBaseURL, sessionId: "two", image: image, client: remote)
        XCTAssertEqual(calls, 2)
    }

    func testImageResponseMustMatchRequestedAttachment() async throws {
        let remote = client { _ in
            (200, ["result": ["ok": true, "value": ["attachment": ["attachmentId": "other"], "data": "YQ=="]]])
        }
        do {
            _ = try await remote.imageAttachment(sessionId: "mine", attachmentId: "requested", baseURL: AppConfig.defaultBaseURL)
            XCTFail("Unrelated attachment must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("图片响应")) }
    }

    func testMissingPromptAcknowledgementDoesNotReportSendSuccess() async throws {
        let remote = client { _ in (200, ["result": ["ok": true, "value": [:]]]) }
        do {
            try await remote.prompt(sessionId: "mine", text: "test")
            XCTFail("Missing acknowledgement must preserve the draft")
        } catch { XCTAssertTrue(error.localizedDescription.contains("未确认接收")) }
    }

    func testRetryKeepsDraftRequestIdentityForServerDeduplication() async throws {
        var identities: [String] = []
        let remote = client { request in
            let root = try self.body(request)
            let args = (root["payload"] as! [String: Any])["args"] as! [String: Any]
            identities.append((args["request"] as! [String: Any])["requestId"] as! String)
            return identities.count == 1 ? (503, [:]) : (200, ["result": ["ok": true, "value": ["accepted": true]]])
        }
        let image = try ImagePreparation.prepare(imageData())
        do { try await remote.prompt(sessionId: "mine", text: "", images: [image], requestId: "same-draft") }
        catch { }
        try await remote.prompt(sessionId: "mine", text: "", images: [image], requestId: "same-draft")
        XCTAssertEqual(identities, ["same-draft", "same-draft"])
    }

    func testInternalContextDoesNotAppearAsUserChatButQuotedTextStillDoes() {
        for kind in ["agent-instructions", "runtime-context", "skill-catalog", "time-context", "system-prompt"] {
            let event: [String: Any] = ["type": "user/message", "seq": 1, "data": [
                "source": ["kind": kind], "content": [["type": "text", "text": "<system-reminder>\nInstructions from: AGENTS.md\ninternal\n</system-reminder>"]],
            ]]
            XCTAssertNil(EventParser.message(from: event, fallbackSeq: 0))
        }
        let quote: [String: Any] = ["type": "user/message", "seq": 2, "data": [
            "source": ["kind": "user"], "content": [["type": "text", "text": "<system-reminder> user quote"]],
        ]]
        XCTAssertNotNil(EventParser.message(from: quote, fallbackSeq: 0))
        let legacy: [String: Any] = ["type": "user/message", "seq": 3, "data": [
            "content": [["type": "text", "text": "<system-reminder> legacy user quote"]],
        ]]
        XCTAssertNotNil(EventParser.message(from: legacy, fallbackSeq: 0))
    }
}
