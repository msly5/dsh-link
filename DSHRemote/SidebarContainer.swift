import SwiftUI

/// Keep the active chat mounted while revealing navigation underneath it.
struct SidebarContainer<Sidebar: View, Content: View>: View {
    @Binding var isPresented: Bool
    @Binding var isExpandedLayout: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content
    @GestureState private var translation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            let expanded = horizontalSizeClass == .regular && geometry.size.width >= 820
            let width = expanded ? 320 : min(max(geometry.size.width * 0.76, 240), 340)
            let offset = expanded ? (isPresented ? width : 0) : min(max((isPresented ? width : 0) + translation, 0), width)
            let detailWidth = max(0, geometry.size.width - (expanded ? offset : 0))
            ZStack(alignment: .leading) {
                Theme.sidebar.ignoresSafeArea()
                sidebar()
                    .frame(width: width, height: geometry.size.height)
                    .overlay(alignment: .trailing) {
                        if expanded { Rectangle().fill(Theme.stroke).frame(width: 0.75) }
                    }
                    .offset(x: expanded && !isPresented ? -width : 0)
                    .accessibilityHidden(!isPresented)
                // Keep a single content subtree through rotation and window resizing so
                // the current stream, scroll position, and unsent draft remain mounted.
                content()
                    .frame(width: detailWidth, height: geometry.size.height)
                    .background(Theme.bg.ignoresSafeArea())
                    .accessibilityHidden(!expanded && isPresented)
                    .allowsHitTesting(expanded || !isPresented)
                    .overlay {
                        if !expanded && isPresented {
                            Button("收起侧栏") { setPresented(false) }
                                .font(.body).foregroundStyle(.clear)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(.rect)
                                .background(Theme.bg.opacity(0.72))
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(.rect(cornerRadius: !expanded && offset > 0 ? 32 : 0))
                    .shadow(color: .black.opacity(!expanded && offset > 0 ? 0.10 : 0), radius: 16, x: -4)
                    .offset(x: offset)
            }
            .clipped()
            .simultaneousGesture(edgeGesture(width: width, enabled: !expanded))
            .onChange(of: expanded, initial: true) { wasExpanded, expanded in
                isExpandedLayout = expanded
                if expanded { isPresented = true }
                else if wasExpanded { isPresented = false }
            }
        }
        .background((isPresented ? Theme.sidebar : Theme.bg).ignoresSafeArea())
    }

    private func edgeGesture(width: CGFloat, enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($translation) { value, state, _ in
                guard enabled, (isPresented || value.startLocation.x < 18),
                      abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                state = isPresented ? min(value.translation.width, 0) : max(value.translation.width, 0)
            }
            .onEnded { value in
                guard enabled, (isPresented || value.startLocation.x < 18),
                      abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                let projected = (isPresented ? width : 0) + value.predictedEndTranslation.width
                setPresented(projected > width * 0.45)
            }
    }

    private func setPresented(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { isPresented = value }
    }
}
