import SwiftUI
import ClerkKit
import GoogleMaps
import UIKit

// MARK: - Deep link routing

/// Single funnel for every ride-invite deep link, regardless of how iOS delivered it. Parses both
/// the legacy custom scheme (convotrack://join/CODE) and the HTTPS Universal Link
/// (https://<host>/convotrack/join/CODE), then hands the 6-char code to the UI.
enum DeepLinkRouter {
    /// Buffers a code parsed before `MainTabView` is on screen and listening (cold launch through
    /// splash → auth). `MainTabView` drains this on appear; the live `NotificationCenter` post
    /// covers the warm/backgrounded case.
    static var pendingJoinCode: String?

    static func handle(_ url: URL) {
        let rawSegment: String?
        if url.scheme == "convotrack", url.host == "join" {
            rawSegment = url.pathComponents.first(where: { $0 != "/" })
        } else if url.scheme == "https",
                  url.host == AppURLs.joinLinkHost,
                  url.path.hasPrefix("/convotrack/join/") {
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
                .task {
                    // Both run in parallel: local StoreKit (works offline) + server plan
                    async let localCheck: () = membershipStore.refreshEntitlements()
                    async let remoteCheck = try? APIClient.shared.fetchMe()
                    let (_, me) = await (localCheck, remoteCheck)
                    // OR logic: local StoreKit is authoritative — server can only upgrade,
                    // not downgrade a valid local entitlement.
                    if let me {
                        membershipStore.isPremium = membershipStore.isPremium || me.plan.isPremium
                    }
                }
        }
    }
}

extension Notification.Name {
    static let convotrackJoinRide = Notification.Name("convotrackJoinRide")
}
