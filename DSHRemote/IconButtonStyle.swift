import SwiftUI

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(width: 44, height: 44)
            .foregroundStyle(Theme.text)
            .background(configuration.isPressed ? Theme.raised : Theme.card, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke) }
    }
}
