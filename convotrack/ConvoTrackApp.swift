import SwiftUI
import ClerkKit
import GoogleMaps

final class ConvoTrackAppDelegate: NSObject, UIApplicationDelegate {
    static var landscapeAllowed = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.landscapeAllowed ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }
}

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
                .onOpenURL { url in handleDeepLink(url) }
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

    // Handles both the legacy custom scheme (convotrack://join/CODE) and the
    // HTTPS Universal Link (https://<host>/convotrack/join/CODE). SwiftUI's
    // .onOpenURL delivers both; universal links only arrive here once the
    // Associated Domains entitlement + backend AASA file are in place.
    private func handleDeepLink(_ url: URL) {
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
        // Post through NotificationCenter so MainTabView can react
        // regardless of where it is in the hierarchy
        NotificationCenter.default.post(
            name: .convotrackJoinRide,
            object: nil,
            userInfo: ["code": code]
        )
    }
}

extension Notification.Name {
    static let convotrackJoinRide = Notification.Name("convotrackJoinRide")
}
