import SwiftUI
import ClerkKit

@main
struct convoyApp: App {
    init() {
        // Replace with your key from dashboard.clerk.com → API Keys
        Clerk.configure(publishableKey: "pk_test_d2VsbC1raXdpLTk2LmNsZXJrLmFjY291bnRzLmRldiQ")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(Clerk.shared)
        }
    }
}
