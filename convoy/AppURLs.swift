import Foundation

// MARK: - Legal URL constants
// TODO: [B6] Ensure https://danglingmind.com/privacy is published and reachable before
// App Store submission. Apple reviewers click this link — a 404 causes rejection.
enum AppURLs {
    static let privacyPolicy = "https://vynl.in/convoy/privacy"
    static let termsOfService = "https://vynl.in/convoy/terms"
    // Single source of truth for the backend — used by both APIClient and SocketClient
    static let backendBaseURL = URL(string: "https://convoy-backend-hx3c.onrender.com")!
}
