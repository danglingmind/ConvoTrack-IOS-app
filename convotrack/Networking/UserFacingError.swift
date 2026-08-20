import Foundation

/// Turns anything thrown in the app into something a rider can actually read.
///
/// The backend answers failures with machine codes — `QUOTA_EXCEEDED`, `NOT_LEADER`,
/// `RIDE_NOT_IN_LOBBY` — and `APIClientError.serverError` carried them straight into
/// `errorDescription`, so alerts showed the rider a constant from a server file. Every alert in
/// the app now reads `error.riderMessage` instead, which means a new backend code can only ever
/// degrade to the generic fallback below, never leak as raw text.
///
/// House style for these strings:
/// - **Say what happened first**, joke second. The rider is usually on a bike.
/// - **Say what to do** when there is something to do ("upgrade", "sign in again", "try again").
/// - **No jokes about safety.** Emergency and location failures are written straight; a rider
///   reading one of those is having a bad day already.
enum UserFacingError {

    /// Message for a backend error code. Returns nil for codes with no rider-facing meaning
    /// (API misuse, validation the client should have prevented) so they fall through to the
    /// generic message rather than getting a jokey one they don't deserve.
    static func message(forCode code: String) -> String? {
        switch code {

        // MARK: Plan limits
        case "QUOTA_EXCEEDED":
            return "You've hit your plan's ride limit. Your enthusiasm is outriding your subscription — upgrade to keep the convoys coming."

        // MARK: Permission
        case "NOT_LEADER", "NOT_AUTHORIZED":
            return "Only the ride leader can do that. Nice try, though."
        case "UNAUTHORIZED", "INVALID_TOKEN":
            return "Your session wandered off. Sign in again and we'll pick up where you left off."
        case "NOT_IN_RIDE", "NOT_A_PARTICIPANT":
            return "You're not in this ride, so there's nothing here to change."
        case "CANNOT_REMOVE_LEADER":
            return "You can't remove the ride leader from their own ride. Bold of you to try."

        // MARK: Joining
        case "RIDE_FULL":
            return "That convoy is packed mirror to mirror. No room for one more."
        case "ALREADY_JOINED":
            return "You're already in this one. Twice as committed, but once is enough."
        case "INVITE_CODE_NOT_FOUND":
            return "No convoy answers to that code. Check the letters and try again — O and 0 are the usual culprits."

        // MARK: Ride state
        case "RIDE_NOT_FOUND":
            return "That ride has vanished. Either it was deleted, or it was never here."
        case "RIDE_ENDED", "RIDE_NOT_COMPLETED":
            return "That ride is already in the history books."
        case "RIDE_NOT_ACTIVE", "RIDE_NOT_ACTIVE_OR_PAUSED":
            return "That ride isn't rolling right now, so there's nothing to update."
        case "RIDE_NOT_LOBBY", "RIDE_NOT_IN_LOBBY":
            return "This ride has already set off — too late to change the plan."
        case "RIDE_NOT_PAUSED":
            return "This ride isn't paused, so there's nothing to resume."

        // MARK: Ride setup
        case "MISSING_REQUIRED_FIELDS":
            return "Some details are still missing. Fill in the blanks and try again."
        case "INVALID_WAYPOINTS":
            return "This route needs somewhere to end up. Add a destination and try again."

        // MARK: Profile
        case "USERNAME_TAKEN":
            return "Another rider got there first. Pick a different name."
        case "USER_NOT_FOUND":
            return "We couldn't find that rider."

        // MARK: Purchases
        case "INVALID_PRODUCT_ID", "INVALID_TRANSACTION", "INVALID_TRANSACTION_PAYLOAD":
            return "The App Store sent something we couldn't make sense of. Nothing was charged — try again."
        case "TRANSACTION_EXPIRED":
            return "That purchase expired before we could confirm it. Nothing was charged."
        case "SANDBOX_TRANSACTION_IN_PRODUCTION":
            return "That was a test purchase, and this isn't a test. Nothing was charged."

        // MARK: Written straight — no jokes on safety
        case "EMERGENCY_NOT_FOUND":
            return "That emergency has already been cleared."
        case "USE_EMERGENCY_EVENT":
            return "Emergencies are raised from the SOS control, not here."
        case "REGROUP_NOT_FOUND":
            return "That regroup has already finished."
        case "PARTICIPANT_NOT_FOUND":
            return "That rider isn't in the convoy any more."

        // MARK: Server's fault
        case "INTERNAL_SERVER_ERROR":
            return "Our server dropped its chain. Give it a moment and try again."

        default:
            return nil
        }
    }

    /// Shown when nothing more specific is known — an unmapped code, or a failure that never
    /// reached the server at all.
    static let generic = "Something went sideways on our end. Give it another go."
    static let offline = "No signal out here. Find some bars and try again."
    static let timedOut = "The server's taking the scenic route. Try again in a moment."
    static let notSignedIn = "You're not signed in — do that first and we'll get you rolling."
    static let unreadableResponse = "The server answered in a language we don't speak. Try again."
    /// StoreKit failures. Reassurance about not being charged goes first — that's the rider's
    /// actual worry — and only reached on a real failure, never on a cancelled purchase.
    static let purchaseFailed = "The App Store wasn't having it. Nothing was charged — try again."
    static let restoreFailed = "Couldn't dig up your previous purchases. Try again in a moment."
}

extension Error {
    /// The string to put in front of a rider. Never a raw error code.
    var riderMessage: String {
        if let apiError = self as? APIClientError {
            switch apiError {
            case .serverError(let code):
                // Codes arrive bare, but tolerate a wrapped/prefixed form too.
                if let mapped = UserFacingError.message(forCode: code) { return mapped }
                if let matched = UserFacingError.knownCodes.first(where: { code.contains($0) }),
                   let mapped = UserFacingError.message(forCode: matched) { return mapped }
                return UserFacingError.generic
            case .notAuthenticated:
                return UserFacingError.notSignedIn
            case .decodingError:
                return UserFacingError.unreadableResponse
            case .networkError(let underlying):
                return (underlying as NSError).riderNetworkMessage
            }
        }
        return (self as NSError).riderNetworkMessage
    }
}

private extension NSError {
    /// Connectivity gets its own wording — "check your connection" is actionable in a way that
    /// the generic message isn't.
    var riderNetworkMessage: String {
        guard domain == NSURLErrorDomain else { return UserFacingError.generic }
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
             NSURLErrorDataNotAllowed, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return UserFacingError.offline
        case NSURLErrorTimedOut:
            return UserFacingError.timedOut
        default:
            return UserFacingError.generic
        }
    }
}

extension UserFacingError {
    /// Every code we have wording for, used for substring matching when a code arrives wrapped
    /// in other text. Kept next to `message(forCode:)` so the two can't drift.
    static let knownCodes = [
        "QUOTA_EXCEEDED", "NOT_LEADER", "NOT_AUTHORIZED", "UNAUTHORIZED", "INVALID_TOKEN",
        "NOT_IN_RIDE", "NOT_A_PARTICIPANT", "CANNOT_REMOVE_LEADER", "RIDE_FULL", "ALREADY_JOINED",
        "INVITE_CODE_NOT_FOUND", "RIDE_NOT_FOUND", "RIDE_ENDED", "RIDE_NOT_COMPLETED",
        "RIDE_NOT_ACTIVE_OR_PAUSED", "RIDE_NOT_ACTIVE", "RIDE_NOT_IN_LOBBY", "RIDE_NOT_LOBBY",
        "RIDE_NOT_PAUSED", "MISSING_REQUIRED_FIELDS", "INVALID_WAYPOINTS", "USERNAME_TAKEN",
        "USER_NOT_FOUND", "INVALID_PRODUCT_ID", "INVALID_TRANSACTION_PAYLOAD", "INVALID_TRANSACTION",
        "TRANSACTION_EXPIRED", "SANDBOX_TRANSACTION_IN_PRODUCTION", "EMERGENCY_NOT_FOUND",
        "USE_EMERGENCY_EVENT", "REGROUP_NOT_FOUND", "PARTICIPANT_NOT_FOUND", "INTERNAL_SERVER_ERROR",
    ]
}
