import Foundation

/// Groups adjacent tool results for display without changing the conversation log.
struct ChatTimelineItem: Identifiable {
    let id: String
    let isToolGroup: Bool
    private(set) var messages: [ChatMessage]

    private init(message: ChatMessage) {
        isToolGroup = message.role == .tool
        id = isToolGroup ? "tools:" + message.id : message.id
        messages = [message]
    }

    static func grouped(_ messages: [ChatMessage]) -> [Self] {
        var items: [Self] = []
        for message in messages {
            if message.role == .tool, let last = items.indices.last, items[last].isToolGroup {
                items[last].messages.append(message)
            } else {
                items.append(Self(message: message))
            }
        }
        return items
    }
}
