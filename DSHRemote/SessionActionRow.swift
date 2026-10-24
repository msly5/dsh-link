import SwiftUI

struct SessionActionRow: View {
    let session: SessionSummary
    var desktopGroup: String?
    var compact = false
    var selected = false
    var archived = false
    let updating: Bool
    let actionsEnabled: Bool
    let onSelect: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                SessionRowView(session: session, desktopGroup: desktopGroup, compact: compact, selected: selected)
            }.buttonStyle(NavigationRowButtonStyle())
            if updating {
                ProgressView().frame(width: 44, height: 44).accessibilityLabel("正在同步归档状态")
            } else {
                Menu {
                    archiveButton
                } label: {
                    Image(systemName: "ellipsis").font(.body).foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .disabled(!actionsEnabled)
                .accessibilityLabel("会话操作：\(session.title)")
            }
        }
        .contextMenu { archiveButton.disabled(!actionsEnabled) }
    }

    private var archiveButton: some View {
        Button(archived ? "恢复会话" : "归档会话", systemImage: archived ? "arrow.uturn.backward" : "archivebox", action: onArchive)
    }
}
