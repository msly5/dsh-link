import SwiftUI
import UserNotifications

extension Notification.Name {
    static let dshOpenSession = Notification.Name("dsh.openSession")
}

/// 把 APNs device token 交给 Mac 代理
enum PushRegistrar {
    static var isAvailable: Bool { Bundle.main.infoDictionary?["DSHEnablePush"] as? String == "YES" }
    static func enableNotifications() {
        guard isAvailable, AppConfig.isConfigured else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
    static func register(token: String) async {
        guard isAvailable, AppConfig.isConfigured, UserDefaults.standard.bool(forKey: "pushEnabled") else { return }
        var req = URLRequest(url: AppConfig.baseURL.appending(path: "push/register"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in AppConfig.accessHeaders(for: AppConfig.baseURL) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        do {
            let session = SecureTransport.session()
            defer { session.finishTasksAndInvalidate() }
            let (_, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[dsh] push register status \(status)")
        } catch {
            print("[dsh] push registration failed")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if ProcessInfo.processInfo.arguments.contains("--no-push") { return true }
        if UserDefaults.standard.bool(forKey: "pushEnabled") { PushRegistrar.enableNotifications() }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PushRegistrar.register(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[dsh] APNs registration failed")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let sessionId = info["sessionId"] as? String, !sessionId.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(name: .dshOpenSession, object: sessionId)
            }
        }
    }
}
