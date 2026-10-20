import Foundation

extension ChatMessage {
    /// Calls and results share an id; keep the original position and enrich it as events arrive.
    func combiningExecution(_ next: ChatMessage) -> ChatMessage {
        guard let earlier = activity, let later = next.activity,
              earlier.kind == .tool, later.kind == .tool else { return next }
        let result = later.phase == .running ? self : next
        var metadata = ExecutionActivity(kind: .tool,
                                         name: later.name ?? earlier.name,
                                         arguments: later.arguments ?? earlier.arguments,
                                         phase: result.activity?.phase ?? .running)
        metadata.phase = metadata.settledPhase(output: result.text)
        return ChatMessage(id: id, seq: min(seq, next.seq), role: .tool,
                           text: result.text, images: result.images, activity: metadata)
    }
}
