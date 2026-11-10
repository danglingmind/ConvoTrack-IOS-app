import Foundation
import UIKit
import UserNotifications
import ClerkKit

/// Push notifications (contract: docs/notifications-plan.md). Owns the permission prompt, the APNs
/// token upload (`PUT /devices`) and removal (`DELETE /devices/:token`). The text is localized on
/// device from the payload's `loc-key` (`push.ride_started.body`, `push.ride_ended.body`).
@MainActor
enum PushNotifications {
    private static let askedKey = "push.permissionAsked"
    private static let tokenKey = "push.apnsToken"

    /// Set by the lobby / navigation screens while they are on screen; a foreground banner for
    /// that same ride is suppressed.
    private static var visibleCounts: [String: Int] = [:]

    /// Order-independent: each screen calls `screenAppeared` / `screenDisappeared` with the same id.
    static func screenAppeared(_ rideId: String?) {
        guard let rideId else { return }
        visibleCounts[rideId, default: 0] += 1
    }
    static func screenDisappeared(_ rideId: String?) {
        guard let rideId, let n = visibleCounts[rideId] else { return }
        visibleCounts[rideId] = n > 1 ? n - 1 : nil
    }
    static func isVisible(_ rideId: String) -> Bool { visibleCounts[rideId] != nil }

    private static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    private static var isSignedIn: Bool { Clerk.shared.user != nil }

    /// Right after the rider first joins or creates a ride. Asks once, ever.
    static func requestPermissionAfterFirstRide() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// App open while signed in: refresh the token if permission was already granted.
    static func registerIfAuthorized() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                UIApplication.shared.registerForRemoteNotifications()
                await upload()
            default: break
            }
        }
    }

    static func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await upload() }
    }

    private static func upload() async {
        guard isSignedIn, let token else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        try? await APIClient.shared.registerDevice(token: token, locale: Locale.current.identifier, appVersion: version)
    }

    /// Call BEFORE the Clerk sign-out: the request needs the session.
    static func unregister() async {
        guard let token else { return }
        do { try await APIClient.shared.unregisterDevice(token: token) }
        catch { try? await APIClient.shared.unregisterDevice(token: token) }
        self.token = nil
    }

    // MARK: Foreground / tap

    static func shouldPresentInForeground(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let rideId = userInfo["rideId"] as? String else { return true }
        return !isVisible(rideId)
    }

    static func handleTap(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, let rideId = userInfo["rideId"] as? String else { return }
        DeepLinkRouter.handleNotification(type: type, rideId: rideId)
    }
}

extension ConvoTrackAppDelegate: UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotifications.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        return await MainActor.run {
            PushNotifications.shouldPresentInForeground(info) ? [.banner, .sound, .list] : []
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run { PushNotifications.handleTap(info) }
    }
}
