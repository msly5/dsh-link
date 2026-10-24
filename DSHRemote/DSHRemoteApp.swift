import SwiftUI

@main
struct DSHRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if DesignPreview.enabled {
                    SessionListView().environment(\.dynamicTypeSize,
                        ProcessInfo.processInfo.arguments.contains("--preview-large") ? .accessibility3 : .large)
                        .preferredColorScheme(DesignPreview.colorScheme)
                } else { SessionListView() }
                #else
                SessionListView()
                #endif
            }
                .tint(Theme.accent)
        }
    }
}
