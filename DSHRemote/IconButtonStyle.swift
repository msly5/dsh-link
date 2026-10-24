import SwiftUI

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: 44, height: 44)
            .foregroundStyle(Theme.text)
            .background(configuration.isPressed ? Theme.raised : .clear, in: .circle)
            .contentShape(.circle)
    }
}
