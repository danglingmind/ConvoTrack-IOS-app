import Foundation

// MARK: - Legal URL constants
// TODO: [B6] Ensure https://convotrack.in/privacy and /terms are published and reachable
// before App Store submission. Apple reviewers click these links — a 404 causes rejection.
// NOTE: served by the `convotrack-website` repo at app/{privacy,terms} on the convotrack.in domain.
enum AppURLs {
    static let privacyPolicy = "https://convotrack.in/privacy"
    static let termsOfService = "https://convotrack.in/terms"
    // Single source of truth for the backend — used by both APIClient and SocketClient.
    // Custom subdomain on Render (api.convotrack.in), part of the unified convotrack.in domain.
    static let backendBaseURL = URL(string: "https://api.convotrack.in")!

    // MARK: - Ride invite deep links
    // Shared invite links must be real HTTPS Universal Links, not the
    // `convotrack://` custom scheme (that isn't tappable in messaging apps and
    // has no fallback when the app isn't installed). This host must match the
    // Associated Domains entitlement (`applinks:<host>`) and the AASA file
    // served by the website (convotrack-website on Vercel) at
    // https://convotrack.in/.well-known/apple-app-site-association.
    static let joinLinkHost = "convotrack.in"

    /// Path prefix for invite links on `joinLinkHost`, e.g. /join/ABC123.
    /// Must match the AASA `components` pattern and the website's /join route.
    static let joinPathPrefix = "/join/"

    /// Canonical shareable invite link, e.g. https://convotrack.in/join/ABC123
    static func joinLink(code: String) -> String {
        "https://\(joinLinkHost)\(joinPathPrefix)\(code)"
    }
}
