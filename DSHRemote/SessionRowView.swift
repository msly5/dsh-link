import SwiftUI

struct SessionRowView: View {
    let session: SessionSummary
    var desktopGroup: String?

    private var project: String {
        guard let cwd = session.cwd else { return "默认工作区" }
        return (cwd as NSString).lastPathComponent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: session.running == true ? "waveform" : "text.bubble")
                .font(.body.weight(.medium))
                .foregroundStyle(session.running == true ? Theme.accent : Theme.violet)
                .frame(width: 42, height: 42)
                .background((session.running == true ? Theme.accent : Theme.violet).opacity(0.09), in: .rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    Image(systemName: "folder").font(.caption)
                    Text(desktopGroup.map { "桌面 · " + $0 } ?? project).lineLimit(1).truncationMode(.middle)
                    if session.running == true {
                        Text("·").foregroundStyle(Theme.muted)
                        Text("运行中").foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .trailing, spacing: 13) {
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.muted.opacity(0.6))
                if let date = session.updatedAtDate {
                    Text(compactRelative(date)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        }
        .padding(17)
        .card(radius: 19)
        .accessibilityElement(children: .combine)
    }
}
