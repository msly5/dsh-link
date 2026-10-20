import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: "terminal.fill")
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: size * 0.29))
            .overlay { RoundedRectangle(cornerRadius: size * 0.29).strokeBorder(Theme.accent.opacity(0.16)) }
            .accessibilityHidden(true)
    }
}
