import SwiftUI

struct ExecutionRow: View {
    let message: ChatMessage
    let sessionId: String
    let serverURL: URL
    var active = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { active && message.activity?.phase == .running }
    private var summary: String {
        message.activity?.kind == .reasoning ? ExecutionActivity.singleLine(message.text) : message.activity?.summary(output: message.text) ?? ExecutionActivity.singleLine(message.text)
    }
    private var title: String { message.activity?.title ?? "执行结果" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: message.activity?.symbol ?? "terminal")
                        .font(.footnote).frame(width: 18)
                    Text(title + (summary.isEmpty ? "" : " · " + String(summary.prefix(220))))
                        .font(.footnote).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isRunning { ProgressView().controlSize(.mini).tint(Theme.muted) }
                    else if message.activity?.phase == .failed {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning)
                    }
                }
                .foregroundStyle(message.activity?.phase == .failed ? Theme.warning : Theme.muted)
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue((isRunning ? "运行中，" : "") + (expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let activity = message.activity, activity.kind == .tool, !activity.input.isEmpty {
                        Text("输入").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        executionText(activity.input)
                    }
                    if !message.text.isEmpty {
                        if message.activity?.kind != .reasoning {
                            Text("输出").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        executionText(message.text)
                    } else if message.activity?.kind == .tool {
                        Text(isRunning ? "正在等待执行结果…" : "暂无输出").font(.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                        ChatImageView(image: image, sessionId: sessionId, serverURL: serverURL)
                    }
                }
                .padding(12).background(Theme.code, in: .rect(cornerRadius: 10))
                .padding(.leading, 27).padding(.bottom, 8)
            }
        }
    }

    private func executionText(_ text: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text).font(.caption.monospaced()).foregroundStyle(Theme.muted)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded.toggle() }
    }
}
