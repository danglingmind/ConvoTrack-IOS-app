import Foundation
import UIKit

/// Product analytics (PostHog). Interface-level events only: screens, onboarding, sharing,
/// permissions, sign-in. Ride lifecycle, safety and revenue events are captured by the backend
/// (`convoy-backend/src/services/analytics.ts`), which is the only place that knows they really
/// happened. Paywall events go through `PaywallAnalytics` → `POST /events`, and the backend
/// forwards them, so they are deliberately not sent from here too.
///
/// Talks to PostHog's `/batch/` endpoint directly rather than through their SDK, because this
/// project has no package dependencies and the surface needed is small.
///
/// Privacy: the rider is identified by their Clerk user id and nothing else. Never put coordinates,
/// place names, invite codes, names, emails or phone numbers in a property. The taxonomy lives in
/// `docs/analytics.md`; keep it, `Analytics.Event`, and the Android `Analytics.Event` in step.
///
/// Off until `apiKey` is set, in DEBUG builds (unless `-analyticsDebug YES`), and when the rider
/// has opted out (`Analytics.isOptedOut`).
@MainActor
enum Analytics {
    /// The PostHog project API key. It is a public, write-only token, safe to ship in the binary
    /// (same as the Maps and Clerk keys). Empty = analytics is off.
    static let apiKey = "phc_zvvzEU6Es8pNGoDKJnAbBwH8gfJ6pt5ENq3BLoD96n3D"
    /// `https://us.i.posthog.com` or `https://eu.i.posthog.com`, matching the project's region.
    static let host = "https://us.i.posthog.com"

    // MARK: Events

    /// The wire names. Past tense, snake_case, one name per meaning.
    enum Event: String {
        // App lifecycle
        case appOpened = "app_opened"
        // Onboarding & auth
        case onboardingStepViewed = "onboarding_step_viewed"
        case onboardingCompleted = "onboarding_completed"
        case packSizeSelected = "pack_size_selected"
        case signInStarted = "sign_in_started"
        case signInSucceeded = "sign_in_succeeded"
        case signInFailed = "sign_in_failed"
        case signedOut = "signed_out"
        // Navigation
        case screenViewed = "screen_viewed"
        case deepLinkOpened = "deep_link_opened"
        // Rides (interface side; the server records the outcome)
        case createRideFailed = "create_ride_failed"
        case joinSheetOpened = "join_sheet_opened"
        case joinFailed = "join_failed"
        case qrScanOpened = "qr_scan_opened"
        case inviteShareOpened = "invite_share_opened"
        case rideSummaryViewed = "ride_summary_viewed"
        case rideSummaryShared = "ride_summary_shared"
        // Permissions
        case permissionResult = "permission_result"
        case voiceMuteToggled = "voice_mute_toggled"
    }

    typealias Props = [String: Any]

    // MARK: Public API

    static var isOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: optOutKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: optOutKey)
            if newValue { queue.removeAll() }
        }
    }

    /// Call once at launch.
    static func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { flushInBackground() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { capture(.appOpened, ["cold": false]) }
        }
        capture(.appOpened, ["cold": true])
    }

    static func capture(_ event: Event, _ props: Props = [:]) {
        enqueue(name: event.rawValue, props: props)
    }

    static func screen(_ name: String) {
        capture(.screenViewed, ["screen": name])
    }

    /// Tie this device's earlier anonymous events to the signed-in rider. Safe to call repeatedly.
    static func identify(userId: String) {
        guard userId != currentUserId else { return }
        let anon = anonId
        currentUserId = userId
        enqueue(name: "$identify", props: ["$anon_distinct_id": anon])
    }

    /// Sign-out: stop attributing to the old rider and start a fresh anonymous identity.
    static func reset() {
        capture(.signedOut)
        flushNow()
        currentUserId = nil
        UserDefaults.standard.set(UUID().uuidString, forKey: anonIdKey)
    }

    /// The rider's plan tier, attached to every event so any chart can be split by it.
    static func setAccess(_ access: MembershipStore.Access) {
        accessName = switch access {
        case .pro: "pro"
        case .trial: "trial"
        case .trialExpired: "trialExpired"
        case .free: "free"
        }
    }

    // MARK: Internals

    private static let optOutKey = "analytics.optOut"
    private static let anonIdKey = "analytics.anonId"
    private static let maxBatch = 50
    private static let maxQueue = 200
    private static let flushDelay: Duration = .seconds(5)

    private static var started = false
    private static var currentUserId: String?
    private static var accessName: String?
    private static var queue: [[String: Any]] = []
    private static var flushTask: Task<Void, Never>?
    private static var sending = false

    private static var anonId: String {
        if let id = UserDefaults.standard.string(forKey: anonIdKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: anonIdKey)
        return id
    }

    private static var enabled: Bool {
        guard !apiKey.isEmpty, !isOptedOut else { return false }
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "analyticsDebug")
        #else
        return true
        #endif
    }

    private static let superProps: Props = {
        let info = Bundle.main.infoDictionary
        return [
            "platform": "ios",
            "$app_version": info?["CFBundleShortVersionString"] as? String ?? "",
            "$app_build": info?["CFBundleVersion"] as? String ?? "",
            "$os": "iOS",
            "$os_version": UIDevice.current.systemVersion,
            "$lib": "convotrack-ios",
            "$locale": Locale.current.identifier,
            "source": "client",
        ]
    }()

    private static func enqueue(name: String, props: Props) {
        guard enabled else { return }
        var merged = superProps
        if let accessName { merged["access"] = accessName }
        for (key, value) in props { merged[key] = value }
        queue.append([
            "event": name,
            "distinct_id": currentUserId ?? anonId,
            "properties": merged,
            "timestamp": ISO8601DateFormatter.fractional.string(from: Date()),
        ])
        // Bounded so an offline rider can't grow it; the oldest go first.
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        scheduleFlush()
    }

    private static func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: flushDelay)
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private static func flushNow() {
        flushTask?.cancel()
        Task { await flush() }
    }

    /// A short background-task window so the last events of a session aren't lost on backgrounding.
    private static func flushInBackground() {
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(taskId) }
        Task {
            await flush()
            if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
        }
    }

    private static func flush() async {
        guard enabled, !sending, !queue.isEmpty,
              let url = URL(string: host + "/batch/") else { return }
        sending = true
        defer { sending = false }
        while !queue.isEmpty {
            let batch = Array(queue.prefix(maxBatch))
            queue.removeFirst(batch.count)
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["api_key": apiKey, "batch": batch]
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { continue }
            request.httpBody = data
            let ok: Bool
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            } catch {
                ok = false
            }
            if !ok {
                // Keep it for the next flush (bounded), and stop rather than spin against a dead host.
                queue.insert(contentsOf: batch, at: 0)
                if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
                scheduleFlush()
                return
            }
        }
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
