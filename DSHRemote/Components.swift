import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.muted)
                .padding(.bottom, 6).accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).lineSpacing(4)
        }.padding(.horizontal, 24)
    }
}
