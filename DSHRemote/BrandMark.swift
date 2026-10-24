import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image("WhaleMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}
