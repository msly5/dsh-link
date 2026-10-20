import SwiftUI

struct ContextGauge: View {
    let ratio: Double

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Theme.stroke, lineWidth: 2)
                Circle().trim(from: 0, to: min(max(ratio, 0), 1))
                    .stroke(ratio > 0.85 ? Theme.warning : Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            Text(ratio, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("上下文已使用")
        .accessibilityValue(ratio.formatted(.percent.precision(.fractionLength(0))))
    }
}
