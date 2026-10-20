import SwiftUI

struct RichText: View {
    let text: String
    var anchorPrefix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlock.parse(text)) { block in
                blockView(block.content, id: block.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ content: MarkdownBlock.Content, id: Int) -> some View {
        switch content {
        case .paragraph(let text):
            inline(text).textSelection(.enabled)
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title2 : level == 2 ? .title3 : .headline)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 6) {
                Label(language.isEmpty ? "代码" : language, systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 8)
                ScrollView(.horizontal) {
                    Text(text).font(.callout.monospaced())
                        .textSelection(.enabled).padding(10)
                }
            }
            .background(Theme.code, in: .rect(cornerRadius: 14))
        case .listItem(let marker, let text, let indent):
            HStack(alignment: .top, spacing: 8) {
                Text(marker).foregroundStyle(.secondary)
                inline(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, Double(indent) * 12)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Theme.accent.opacity(0.7)).frame(width: 3)
                inline(text).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
                .id("table:\(anchorPrefix ?? "markdown"):\(id)")
        case .divider:
            Divider().padding(.vertical, 4)
        }
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text,
             options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }

}
