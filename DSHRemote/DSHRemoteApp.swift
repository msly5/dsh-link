import SwiftUI

@main
struct DSHRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system

    private var colorScheme: ColorScheme? {
        #if DEBUG
        if DesignPreview.enabled, let preview = DesignPreview.colorScheme { return preview }
        #endif
        return appearance.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if DesignPreview.enabled {
                    SessionListView().environment(\.dynamicTypeSize,
                        ProcessInfo.processInfo.arguments.contains("--preview-large") ? .accessibility3 : .large)
                } else { SessionListView() }
                #else
                SessionListView()
                #endif
            }
                .tint(Theme.accent)
                .preferredColorScheme(colorScheme)
        }
    }
}
