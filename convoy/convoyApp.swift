import SwiftUI
import ClerkKit

@main
struct convoyApp: App {
    init() {
        Clerk.configure(publishableKey: "pk_test_d2VsbC1raXdpLTk2LmNsZXJrLmFjY291bnRzLmRldiQ")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
                .onOpenURL { url in
                    handleDeepLink(url)
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
