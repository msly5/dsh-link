import SwiftUI

/// A row activates only on a tap, allowing the surrounding drawer drag to cancel it.
struct NavigationRowButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .onTapGesture { if isEnabled { configuration.trigger() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { configuration.trigger() } }
    }
}
