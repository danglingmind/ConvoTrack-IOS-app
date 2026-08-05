import Foundation

// MARK: - Legal URL constants
// TODO: [B6] Ensure https://vynl.in/convotrack/privacy and /terms are published and reachable
// before App Store submission. Apple reviewers click these links — a 404 causes rejection.
// NOTE: served by the `noto` repo at src/app/convotrack/{privacy,terms} (clean cutover, no /convoy redirect).
enum AppURLs {
    static let privacyPolicy = "https://vynl.in/convotrack/privacy"
    static let termsOfService = "https://vynl.in/convotrack/terms"
    // Single source of truth for the backend — used by both APIClient and SocketClient
    // TODO: [rename] Render host still named `convoy-backend`. Rename the Render service (or
    // add a custom domain) and update this URL — the `-hx3c` suffix is Render-assigned, so the
    // new host isn't predictable from here. Left as-is to avoid breaking all API/socket calls.
    static let backendBaseURL = URL(string: "https://convoy-backend-hx3c.onrender.com")!

    // MARK: - Ride invite deep links
    // Shared invite links must be real HTTPS Universal Links, not the
    // `convotrack://` custom scheme (that isn't tappable in messaging apps and
    // has no fallback when the app isn't installed). This host must match the
    // Associated Domains entitlement (`applinks:<host>`) and the backend's
    // apple-app-site-association file.
    static let joinLinkHost = "convoy-backend-hx3c.onrender.com"

    /// Canonical shareable invite link, e.g. https://…/convotrack/join/ABC123
    static func joinLink(code: String) -> String {
        "\(backendBaseURL.absoluteString)/convotrack/join/\(code)"
    }
}
