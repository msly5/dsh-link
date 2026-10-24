import SwiftUI

struct ToolResultGroupView: View {
    let messages: [ChatMessage]
    let sessionId: String
    let serverURL: URL
    var active = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.down").font(.caption2.weight(.medium)).frame(width: 18)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Text(header).font(.footnote).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已收起")

            if expanded {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        ExecutionRow(message: message, sessionId: sessionId, serverURL: serverURL, active: active)
                    }
                }
            }
        }
    }

    private var header: String {
        if active, let current = messages.last(where: { $0.activity?.phase == .running }), let activity = current.activity {
            let summary = activity.kind == .reasoning ? ExecutionActivity.singleLine(current.text) : activity.summary
            return "正在" + activity.title + " · " + String(summary.prefix(220))
        }
        return "查看执行过程 · \(messages.count) 项"
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { expanded.toggle() }
    }
}
