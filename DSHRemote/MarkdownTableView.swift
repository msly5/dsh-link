import SwiftUI

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    @ScaledMetric(relativeTo: .callout) private var preferredColumnWidth = 180.0
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var availableWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    private var needsScrolling: Bool { contentWidth > availableWidth + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if needsScrolling {
                Label("左右滑动查看全部 \(headers.count) 列", systemImage: "arrow.left.and.right")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal) {
                MarkdownTableLayout(columns: headers.count, maximumColumnWidth: preferredColumnWidth,
                                    availableWidth: availableWidth, fitNarrowTables: !typeSize.isAccessibilitySize) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, header: true)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        ForEach(0..<headers.count, id: \.self) { index in
                            cell(index < row.count ? row[index] : "")
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke) }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .padding(.bottom, needsScrolling ? 8 : 0)
            }
            .defaultScrollAnchor(.topLeading)
            .scrollIndicators(.visible)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }

    private func cell(_ text: String, header: Bool = false) -> some View {
        Text((try? AttributedString(markdown: text,
             options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .font(.callout).fontWeight(header ? .semibold : .regular)
            .lineLimit(nil).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(header ? Theme.faint : .clear)
            .overlay { Rectangle().strokeBorder(Theme.stroke, lineWidth: 0.5) }
    }
}
