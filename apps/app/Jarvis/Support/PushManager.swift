#if os(iOS)
import Foundation
import JarvisAPI
import Observation
import UIKit
import UserNotifications

/// Push registration, iPhone only. The Mac build never compiles this file and
/// never asks for a token, which is the whole mechanism behind "notifications
/// on the phone, not the laptop".
///
/// A device token is a fact about this install, not user data, so registration
/// goes straight to the API instead of through the mutation queue: a replayed
/// token after sign-out would re-arm a device the user just signed out of.
@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Set once the token has reached the server, so the UI can tell "allowed"
    /// from "allowed and actually registered".
    private(set) var isRegistered = false

    /// Set by AppModel once it exists. Weak, because AppModel outlives nothing
    /// here and the manager must not keep it alive.
    weak var model: AppModel?

    /// The last token APNs issued, kept so sign-out can revoke the right one
    /// after the app has already forgotten everything else.
    private static var storedToken: String? {
        get { UserDefaults.standard.string(forKey: "jarvis.pushToken") }
        set { UserDefaults.standard.set(newValue, forKey: "jarvis.pushToken") }
    }

    /// The APNs environment this build's token belongs to. Debug builds are
    /// signed with the development entitlement and get sandbox tokens, even
    /// though a Debug build on a real iPhone talks to the production API.
    private var environment: DeviceEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }

    /// Ask for permission, then register. Returns whether the system allowed it.
    /// Called from the settings toggle rather than at launch: a permission
    /// prompt on first open, before the app has shown what it is for, is the
    /// one most reliably denied.
    @discardableResult
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted =
            (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        guard granted else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    /// Registers again if permission is already granted. Safe on every launch:
    /// the server keys on the token, and this is how a rotated token is caught.
    func registerIfAuthorized() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// APNs handed us a token. Send it on.
    func handleToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Self.storedToken = token
        guard let api = model?.api else { return }
        do {
            try await api.registerDevice(token: token, environment: environment)
            isRegistered = true
        } catch {
            // The next launch registers again, so a failure here costs one day
            // of notifications at worst.
            isRegistered = false
            print("Push registration failed: \(error)")
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        isRegistered = false
        print("Push registration was refused by the system: \(error)")
    }

    /// Called on sign-out, before the session token is thrown away.
    func revokeCurrentToken() async {
        guard let token = Self.storedToken, let api = model?.api else { return }
        _ = try? await api.revokeDevice(token: token)
        Self.storedToken = nil
        isRegistered = false
    }
}
#endif
