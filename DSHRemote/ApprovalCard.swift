import SwiftUI

struct ApprovalCard: View {
    let prompt: ApprovalPrompt
    let onAllow: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.warning)
                    .frame(width: 36, height: 36)
                    .background(Theme.warning.opacity(0.10), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("需要你的批准").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(prompt.toolName).font(.caption.monospaced()).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if let reason = prompt.reason, !reason.isEmpty {
                Text(reason).font(.callout).foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("拒绝", action: onReject)
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.raised, in: .rect(cornerRadius: 14))
                Button("允许一次", action: onAllow)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.warning.opacity(0.24)) }
    }
}
