import SwiftUI

struct CommandSuggestionsView: View {
    let commands: [CommandDescriptor]
    let query: String
    let loading: Bool
    let error: String?
    let refresh: () -> Void
    let select: (CommandDescriptor) -> Void

    private var matches: [CommandDescriptor] { commands.filter { $0.name.hasPrefix(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("指令").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button(action: refresh) { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).disabled(loading).accessibilityLabel("刷新指令列表")
            }.padding(.horizontal, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.warning).padding(8)
                    }
                    if matches.isEmpty {
                        Text(loading ? "正在读取指令…" : (error == nil ? "没有匹配的指令" : "点右上角刷新重试"))
                            .font(.footnote).foregroundStyle(Theme.muted).padding(8)
                    }
                    ForEach(matches) { command in
                        Button { select(command) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("/" + command.name).font(.subheadline.monospaced()).foregroundStyle(Theme.text)
                                Text(command.description).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(.rect)
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 150)
            Divider().padding(.top, 6)
        }
        .accessibilityIdentifier("commandSuggestions")
    }
}
