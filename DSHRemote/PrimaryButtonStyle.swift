import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(enabled ? Theme.onAccent : Theme.muted)
            .background(enabled ? Theme.accent : Theme.raised, in: .capsule)
            .opacity(configuration.isPressed ? 0.80 : 1)
    }
}
