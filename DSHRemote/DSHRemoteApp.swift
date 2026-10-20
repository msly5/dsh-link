import SwiftUI

@main
struct DSHRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
