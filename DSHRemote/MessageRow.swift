import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let sessionId: String
    let serverURL: URL
    @State private var toolExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch message.role {
            case .user:
                HStack {
                    Spacer(minLength: 34)
                    VStack(alignment: .trailing, spacing: 10) {
                        imageAttachments
                        if !message.text.isEmpty {
                            Text(message.text)
                                .font(.body).lineSpacing(5)
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                                .padding(.horizontal, 17).padding(.vertical, 14)
                                .background(Theme.code, in: .rect(cornerRadius: 19))
                        }
                    }
                }
                .padding(.vertical, 4)
            case .assistant:
                VStack(alignment: .leading, spacing: 13) {
                    RichText(text: message.text, anchorPrefix: message.id)
                        .font(.body).lineSpacing(5)
                        .foregroundStyle(Theme.text)
                    imageAttachments
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            case .tool:
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toolExpanded.toggle() }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Theme.accent)
                            Text(toolExpanded ? "收起执行结果" : "查看执行结果").font(.caption.monospaced())
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption.weight(.medium))
                                .rotationEffect(.degrees(toolExpanded ? 180 : 0))
                        }
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(toolExpanded ? "已展开" : "已收起")
                    if toolExpanded {
                        Divider().overlay(Theme.stroke)
                        ScrollView(.horizontal) {
                            Text(message.text).font(.caption.monospaced())
                                .foregroundStyle(Theme.muted).textSelection(.enabled).padding(14)
                        }
                        imageAttachments.padding(12)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.stroke) }
            }
        }
    }

    private var imageAttachments: some View {
        ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
            ChatImageView(image: image, sessionId: sessionId, serverURL: serverURL)
        }
    }
}
