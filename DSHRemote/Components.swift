import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Theme.accent)
                .frame(width: 70, height: 70)
                .background(Theme.accent.opacity(0.07), in: .rect(cornerRadius: 23))
                .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(Theme.accent.opacity(0.10)) }
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 24)
    }
}
