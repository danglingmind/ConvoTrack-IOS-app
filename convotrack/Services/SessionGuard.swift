import Foundation
import ClerkKit

extension Clerk {
    /// Signed in with a session the server still honours. `user != nil` alone is not enough: after
    /// weeks idle Clerk keeps the cached user around while its session is `.expired`, so every
    /// request fails with "not signed in" and the UI shows a placeholder rider.
    var isSignedIn: Bool {
        guard user != nil, let status = session?.status else { return false }
        return status == .active || status == .pending
    }
}

enum SessionGuard {
    /// Runs `op` but gives up after `seconds`; nil on timeout or error. Used so a dead session's
    /// network calls can never leave a spinner up forever.
    static func bounded<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await op() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Asks Clerk's server whether the stored session is still alive (so an expired one flips
    /// `isSignedIn` to false). An offline failure changes nothing: no network is not a sign-out.
    @MainActor static func revalidate() async {
        guard Clerk.shared.user != nil else { return }
        _ = await bounded(5) { try await Clerk.shared.refreshClient() }
    }
}
