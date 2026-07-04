import SwiftUI
import ClerkKit
import GoogleMaps

final class ConvoyAppDelegate: NSObject, UIApplicationDelegate {
    static var landscapeAllowed = false

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.landscapeAllowed ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }
}

@main
struct convoyApp: App {
    @UIApplicationDelegateAdaptor(ConvoyAppDelegate.self) var delegate
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

    // Handles convoy://join/INVITECODE
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "convoy",
              url.host == "join" else { return }
        let code = url.pathComponents
            .first(where: { $0 != "/" })?
            .uppercased()
            .filter({ $0.isLetter || $0.isNumber })
            .prefix(6)
            .map(String.init)
            .joined() ?? ""
        guard code.count == 6 else { return }
        // Post through NotificationCenter so MainTabView can react
        // regardless of where it is in the hierarchy
        NotificationCenter.default.post(
            name: .convoyJoinRide,
            object: nil,
            userInfo: ["code": code]
        )
    }
}

extension Notification.Name {
    static let convoyJoinRide = Notification.Name("convoyJoinRide")
}
