import SwiftUI

struct SessionRowView: View {
    let session: SessionSummary
    var desktopGroup: String?
    var compact = false
    var selected = false

    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0
    private var project: String {
        guard let cwd = session.cwd else { return "默认工作区" }
        return (cwd as NSString).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "bubble.left")
                .font(.body).foregroundStyle(Theme.muted)
                .frame(width: iconWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.body).foregroundStyle(Theme.text)
                    .lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    Text(desktopGroup ?? project).font(.caption).foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if session.running == true {
                Image(systemName: "waveform").font(.caption).foregroundStyle(Theme.muted)
                    .accessibilityLabel("运行中")
            } else if !compact, let date = session.updatedAtDate {
                Text(compactRelative(date)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 15 : 17)
        .frame(minHeight: 52)
        .background(selected ? Theme.raised.opacity(0.8) : .clear, in: .rect(cornerRadius: 13))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
