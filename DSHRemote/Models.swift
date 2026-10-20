import Foundation

struct SessionSummary: Codable, Identifiable, Hashable {
    let sessionId: String
    let updatedAt: Double?
    let running: Bool?
    let blank: Bool?
    let cwd: String?
    let projections: Projections?

    var id: String { sessionId }

    var title: String {
        if let t = projections?.values?.title, !t.isEmpty { return t }
        if let cwd { return (cwd as NSString).lastPathComponent }
        return sessionId
    }

    var updatedAtDate: Date? {
        guard let updatedAt else { return nil }
        return Date(timeIntervalSince1970: updatedAt / 1000)
    }
}

struct Projections: Codable, Hashable {
    let values: ProjectionValues?
}

struct ProjectionValues: Codable, Hashable {
    let title: String?
    let contextPressure: ContextPressure?
    let permissions: PermissionsProjection?
    let modelSelection: ModelSelectionProjection?
    let imageLimits: ImageLimits?
}

struct ContextPressure: Codable, Hashable {
    let pressureTokens: Int?
    let projectedTokens: Int?
    let contextWindow: Int?

    var ratio: Double? {
        guard let projectedTokens, let contextWindow, contextWindow > 0 else { return nil }
        return Double(projectedTokens) / Double(contextWindow)
    }
}

struct PermissionsProjection: Codable, Hashable {
    let currentValue: String?
}

struct ModelSelectionProjection: Codable, Hashable {
    let next: SessionModelSelection?
    let lastUsed: SessionModelSelection?
}

struct SessionModelSelection: Codable, Hashable {
    let provider: String?
    let model: String?
    let reasoningEffort: String?
}

struct SessionListValue: Codable {
    let items: [SessionSummary]
}

/// UI 上的一条消息
struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant, tool
    }

    let id: String
    let seq: Int
    let role: Role
    var text: String
    var images: [ChatImage] = []
    var activity: ExecutionActivity?

    enum CodingKeys: String, CodingKey { case id, seq, role, text, images, activity }
}

extension ChatMessage {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        seq = try values.decode(Int.self, forKey: .seq)
        role = try values.decode(Role.self, forKey: .role)
        text = try values.decode(String.self, forKey: .text)
        images = try values.decodeIfPresent([ChatImage].self, forKey: .images) ?? []
        activity = try values.decodeIfPresent(ExecutionActivity.self, forKey: .activity)
    }
}

struct PermissionOption: Codable, Identifiable, Hashable {
    let value: String
    let name: String
    var id: String { value }
}

struct PermissionCatalog: Codable {
    let options: [PermissionOption]
    let defaultPreset: String
}

/// agent 抛给用户的选择题
struct UserQuestion: Identifiable, Hashable {
    let id: String
    let header: String?
    let question: String
    let options: [String]
    let multiSelect: Bool
    var detail: String? = nil
}

struct QuestionPrompt: Identifiable, Hashable {
    let id: String          // eventId
    let questions: [UserQuestion]
}

/// 需要用户在手机上回答的审批
struct ApprovalPrompt: Identifiable, Hashable {
    let id: String          // eventId
    let toolName: String
    let reason: String?
}

// MARK: - 原始事件解析

enum EventParser {
    static func displayMessages(from event: [String: Any], fallbackSeq: Int) -> [ChatMessage] {
        let seq = event["seq"] as? Int ?? fallbackSeq
        let payload = event["data"] as? [String: Any] ?? event
        switch event["type"] as? String {
        case "tool/call":
            guard let callId = payload["callId"] as? String, let name = payload["name"] as? String else { return [] }
            let arguments: String?
            if let raw = payload["arguments"] as? String { arguments = raw }
            else if let value = payload["arguments"], JSONSerialization.isValidJSONObject(value),
                    let data = try? JSONSerialization.data(withJSONObject: value) { arguments = String(decoding: data, as: UTF8.self) }
            else { arguments = nil }
            return [ChatMessage(id: "call:" + callId, seq: seq, role: .tool, text: "",
                                activity: ExecutionActivity(kind: .tool, name: name, arguments: arguments, phase: .running))]
        case "assistant/message":
            let content = (payload["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let reasoning = content.filter { $0["type"] as? String == "reasoning" }.compactMap { $0["text"] as? String }.joined()
            var rows: [ChatMessage] = []
            if !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(ChatMessage(id: "s\(seq)-r", seq: seq, role: .tool, text: reasoning,
                                        activity: ExecutionActivity(kind: .reasoning, phase: .completed)))
            }
            if let message = message(from: event, fallbackSeq: fallbackSeq) { rows.append(message) }
            return rows
        default:
            return message(from: event, fallbackSeq: fallbackSeq).map { [$0] } ?? []
        }
    }

    /// snapshot/page 里的 `records` 可能是 `{type, event}` 或事件本身
    static func event(from record: [String: Any]) -> [String: Any]? {
        if let inner = record["event"] as? [String: Any], inner["type"] != nil {
            return inner
        }
        return record["type"] == nil ? nil : record
    }

    static func textParts(_ content: [[String: Any]]?) -> String {
        guard let content else { return "" }
        return content.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined()
    }

    static func streamText(_ records: [[String: Any]]?) -> String {
        streamText(records, kind: "text")
    }

    static func streamText(_ records: [[String: Any]]?, kind: String) -> String {
        (records ?? []).compactMap { record -> String? in
            if record["type"] as? String == "\(kind)-chunks" {
                return (record["texts"] as? [String])?.joined()
            }
            if record["type"] as? String == "chunk", let chunk = record["chunk"] as? [String: Any],
               chunk["type"] as? String == "\(kind)-delta" { return chunk["text"] as? String }
            return nil
        }.joined()
    }

    static func message(from event: [String: Any], fallbackSeq: Int) -> ChatMessage? {
        let seq = (event["seq"] as? Int) ?? fallbackSeq
        // 事件信封是 { type, seq, time, data }，载荷在 data 里
        let payload = (event["data"] as? [String: Any]) ?? event
        let role: ChatMessage.Role
        let content: [[String: Any]]?
        var activity: ExecutionActivity?
        var callId: String?
        switch event["type"] as? String {
        case "user/message":
            if let kind = (payload["source"] as? [String: Any])?["kind"] as? String,
               ["agent-instructions", "runtime-context", "skill-catalog", "time-context", "system-prompt"].contains(kind) { return nil }
            role = .user
            content = payload["content"] as? [[String: Any]]
        case "assistant/message":
            role = .assistant
            content = (payload["message"] as? [String: Any])?["content"] as? [[String: Any]]
        case "tool/result":
            role = .tool
            let result = payload["message"] as? [String: Any]
            content = result?["content"] as? [[String: Any]]
            callId = (result?["source"] as? [String: Any])?["callId"] as? String ?? result?["toolCallId"] as? String
            activity = ExecutionActivity(kind: .tool, phase: result?["isError"] as? Bool == true ? .failed : .completed)
        default:
            return nil
        }
        let text = textParts(content)
        let images = (content ?? []).compactMap { part -> ChatImage? in
            guard part["type"] as? String == "image", let ref = part["attachment"] as? [String: Any],
                  let id = ref["attachmentId"] as? String, !id.isEmpty,
                  let mediaType = ref["mediaType"] as? String, mediaType.hasPrefix("image/") else { return nil }
            return ChatImage(attachmentId: id, mediaType: mediaType, name: ref["name"] as? String)
        }
        guard !text.isEmpty || !images.isEmpty || activity != nil else { return nil }
        let suffix = role == .user ? "u" : role == .assistant ? "a" : "t"
        return ChatMessage(id: callId.map { "call:" + $0 } ?? "s\(seq)-\(suffix)", seq: seq, role: role, text: text, images: images, activity: activity)
    }
}
