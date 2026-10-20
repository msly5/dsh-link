import Foundation
import XCTest
@testable import DSHRemoteCore

final class ChatTimelineTests: XCTestCase {
    private func message(_ seq: Int, _ role: ChatMessage.Role) -> ChatMessage {
        ChatMessage(id: "message-\(seq)", seq: seq, role: role, text: "result \(seq)")
    }

    func testAdjacentResultsCollapseWithoutCrossingConversationMessages() {
        let messages = [message(1, .user), message(2, .tool), message(3, .tool),
                        message(4, .assistant), message(5, .tool), message(6, .tool), message(7, .user)]
        let items = ChatTimelineItem.grouped(messages)
        XCTAssertEqual(items.map { $0.messages.map(\.seq) }, [[1], [2, 3], [4], [5, 6], [7]])
        XCTAssertEqual(items.map(\.isToolGroup), [false, true, false, true, false])
        XCTAssertEqual(items.flatMap(\.messages), messages)
    }

    func testManyResultsUseOneStableRowAsNewResultsArrive() {
        let earlier = (1...12).map { message($0, .tool) }
        let first = ChatTimelineItem.grouped(earlier)
        let updated = ChatTimelineItem.grouped(earlier + [message(13, .tool)])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(first[0].id, updated[0].id, "Appending a result must not recreate the row and reset its expansion state")
        XCTAssertEqual(updated[0].messages.count, 13)
    }

    func testGroupingPreservesImagesAndUnrelatedMessages() {
        var tool = message(2, .tool)
        tool.images = [ChatImage(attachmentId: "image", mediaType: "image/png", name: "chart.png")]
        let messages = [message(1, .assistant), tool, message(3, .tool), message(4, .assistant), message(5, .assistant)]
        let items = ChatTimelineItem.grouped(messages)
        XCTAssertEqual(items.flatMap(\.messages), messages)
        XCTAssertEqual(items[1].messages[0].images, tool.images)
        XCTAssertEqual(items.suffix(2).map { $0.messages.count }, [1, 1])
        XCTAssertTrue(ChatTimelineItem.grouped([]).isEmpty)
    }
}
