#if os(iOS)
import UIKit
import UserNotifications

/// Exists for one reason: SwiftUI has no scene-level hook for the APNs token
/// callbacks, so the app needs a UIApplicationDelegate to receive them. It
/// holds no state of its own and forwards everything to PushManager.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        // Set before the app finishes launching, so a notification that opened
        // the app from cold is still delivered to the delegate.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        Task { @MainActor in
            await PushManager.shared.handleToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
    ) {
        Task { @MainActor in
            PushManager.shared.handleRegistrationFailure(error)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// The nudge is about today, and Overview is where today is filled in.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        await MainActor.run {
            PushManager.shared.model?.requestedSection = .today
        }
    }

    /// Showing it while the app is open is deliberate: the alternative is a
    /// notification that silently vanishes when the phone is already unlocked
    /// on Jarvis, which reads as a bug.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif
