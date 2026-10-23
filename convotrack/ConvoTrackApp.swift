import SwiftUI
import ClerkKit
import GoogleMaps
import UIKit

// MARK: - Deep link routing

/// Single funnel for every ride-invite deep link, regardless of how iOS delivered it. Parses both
/// the legacy custom scheme (convotrack://join/CODE) and the HTTPS Universal Link
/// (https://convotrack.in/join/CODE), then hands the 6-char code to the UI.
enum DeepLinkRouter {
    /// Buffers a code parsed before `MainTabView` is on screen and listening (cold launch through
    /// splash → auth). `MainTabView` drains this on appear; the live `NotificationCenter` post
    /// covers the warm/backgrounded case.
    static var pendingJoinCode: String?
    /// Same buffering for the Live Activity tap (`convotrack://ride/<id>`).
    static var pendingOpenRideId: String?

    static func handle(_ url: URL) {
        // Live Activity tap: open navigation for the ride. Custom scheme only; it is never shared.
        if url.scheme == "convotrack", url.host == "ride" {
            let id = url.pathComponents.first(where: { $0 != "/" }) ?? ""
            guard !id.isEmpty, id.count <= 64,
                  id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return }
            pendingOpenRideId = id
            Task { @MainActor in Analytics.capture(.deepLinkOpened, ["kind": "ride"]) }
            NotificationCenter.default.post(name: .convotrackOpenRide, object: nil, userInfo: ["rideId": id])
            return
        }
        let rawSegment: String?
        if url.scheme == "convotrack", url.host == "join" {
            rawSegment = url.pathComponents.first(where: { $0 != "/" })
        } else if url.scheme == "https",
                  url.host == AppURLs.joinLinkHost,
                  url.path.hasPrefix(AppURLs.joinPathPrefix) {
            rawSegment = url.lastPathComponent
        } else {
            return
        }
        let code = String(
            (rawSegment ?? "")
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
                .prefix(6)
        )
        guard code.count == 6 else { return }
        pendingJoinCode = code
        Task { @MainActor in Analytics.capture(.deepLinkOpened, ["kind": "join"]) }
        NotificationCenter.default.post(
            name: .convotrackJoinRide,
            object: nil,
            userInfo: ["code": code]
        )
    }

    /// Convenience for scene callbacks that carry an NSUserActivity (universal links).
    static func handle(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return }
        handle(url)
    }
}

// MARK: - App / Scene delegates

final class ConvoTrackAppDelegate: NSObject, UIApplicationDelegate {
    static var landscapeAllowed = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.landscapeAllowed ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }

    // Route every scene to our own delegate so deep links are handled through the scene lifecycle
    // (the only reliable path for Universal Links on a scene-based app — .onOpenURL never sees
    // them, and .onContinueUserActivity is unreliable at cold launch under an app-delegate adaptor).
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ConvoTrackSceneDelegate.self
        return config
    }
}

/// Observes the scene purely to capture deep links. It deliberately does NOT create or touch a
/// `window` — SwiftUI's `App`/`WindowGroup` still installs and owns the UI; this only reads the
/// launch/continue options.
final class ConvoTrackSceneDelegate: NSObject, UIWindowSceneDelegate {
    // Cold launch: the URL / user activity that launched us rides in on the connection options.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        connectionOptions.urlContexts.forEach { DeepLinkRouter.handle($0.url) }        // custom scheme
        connectionOptions.userActivities.forEach { DeepLinkRouter.handle($0) }         // universal link
    }

    // Warm resume via a Universal Link.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        DeepLinkRouter.handle(userActivity)
    }

    // Warm resume via the custom scheme (legacy / QR back-compat).
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { DeepLinkRouter.handle($0.url) }
    }
}

// MARK: - App

@main
struct ConvoTrackApp: App {
    @UIApplicationDelegateAdaptor(ConvoTrackAppDelegate.self) var delegate
    @StateObject private var membershipStore = MembershipStore()

    init() {
        GoogleMapsConfig.initialize()
        Clerk.configure(publishableKey: "pk_live_Y2xlcmsuY29udm95LnZ5bmwuaW4k")
        Analytics.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
                .environmentObject(membershipStore)
                // Fallback path: if this build ever runs without the scene delegate taking effect,
                // SwiftUI still surfaces links here. Handing to the same router keeps it idempotent.
                .onOpenURL { url in DeepLinkRouter.handle(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    DeepLinkRouter.handle(activity)
                }
                // Local StoreKit + server plan/trial/usage, in parallel. Signed-in riders are
                // refreshed again on every foreground by `MainTabView`, which also decides the
                // app-open nudge from the fresh state.
                .task { await membershipStore.refreshServerState() }
        }
    }
}

extension Notification.Name {
    static let convotrackJoinRide = Notification.Name("convotrackJoinRide")
    static let convotrackOpenRide = Notification.Name("convotrackOpenRide")
}
