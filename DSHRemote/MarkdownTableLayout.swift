import SwiftUI

/// Measure every wrapped cell at its column width before allocating the full row height.
struct MarkdownTableLayout: Layout {
    let columns: Int
    let maximumColumnWidth: CGFloat
    let availableWidth: CGFloat
    let fitNarrowTables: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = columnWidths(subviews)
        return CGSize(width: widths.reduce(0, +), height: rowHeights(subviews, widths: widths).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columns > 0 else { return }
        let widths = columnWidths(subviews)
        let heights = rowHeights(subviews, widths: widths)
        var y = bounds.minY
        for row in heights.indices {
            var x = bounds.minX
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: x, y: y),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(width: widths[column], height: heights[row]))
                x += widths[column]
            }
            y += heights[row]
        }
    }

    private func columnWidths(_ subviews: Subviews) -> [CGFloat] {
        guard columns > 0 else { return [] }
        let minimum = maximumColumnWidth * 48 / 180
        var widths = Array(repeating: minimum, count: columns)
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified).width
            widths[index % columns] = max(widths[index % columns], min(ideal, maximumColumnWidth))
        }
        let total = widths.reduce(0, +)
        if availableWidth > total {
            let extra = (availableWidth - total) / CGFloat(columns)
            widths = widths.map { $0 + extra }
        } else if columns <= 2, fitNarrowTables, availableWidth > 0 {
            widths = widths.map { $0 * availableWidth / total }
        }
        return widths
    }

    private func rowHeights(_ subviews: Subviews, widths: [CGFloat]) -> [CGFloat] {
        guard columns > 0 else { return [] }
        var heights = Array(repeating: CGFloat.zero, count: (subviews.count + columns - 1) / columns)
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: widths[index % columns], height: nil)).height
            heights[index / columns] = max(heights[index / columns], height)
        }
        return heights
    }
}
