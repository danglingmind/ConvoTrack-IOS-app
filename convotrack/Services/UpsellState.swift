import Foundation

/// Upsell bookkeeping: app opens, when the nudge and Home card were last shown or dismissed.
/// Plain UserDefaults like `OnboardingState`: nothing here is secret, and losing it only means a
/// rider may see an upsell a little sooner than the cadence would allow.
enum UpsellState {
    private enum Key {
        static let appOpenCount = "upsell.appOpenCount"
        static let firstOpenAt = "upsell.firstOpenAt"
        static let lastBackgroundAt = "upsell.lastBackgroundAt"
        static let lastNudgeAt = "upsell.lastNudgeAt"
        static let nudgeDismissCount = "upsell.nudgeDismissCount"
        static let onboardingPaywallAt = "upsell.onboardingPaywallAt"
        static let rideCompletedAt = "upsell.rideCompletedAt"
        static let homeCardSnoozedUntil = "upsell.homeCardSnoozedUntil"
        static let homeCardDismissCount = "upsell.homeCardDismissCount"
        static let all = [appOpenCount, firstOpenAt, lastBackgroundAt, lastNudgeAt, nudgeDismissCount,
                          onboardingPaywallAt, rideCompletedAt, homeCardSnoozedUntil, homeCardDismissCount]
    }

    private static var defaults: UserDefaults { .standard }

    private static func date(_ key: String) -> Date? { defaults.object(forKey: key) as? Date }
    private static func setDate(_ value: Date?, _ key: String) { defaults.set(value, forKey: key) }

    /// A return to the app only counts as a new "open" after this long in the background, so
    /// glancing at Maps mid-ride and coming back isn't an app open.
    static let reopenGap: TimeInterval = 30 * 60

    static var appOpenCount: Int { defaults.integer(forKey: Key.appOpenCount) }
    static var firstOpenAt: Date? { date(Key.firstOpenAt) }
    static var lastNudgeAt: Date? { date(Key.lastNudgeAt) }
    static var nudgeDismissCount: Int { defaults.integer(forKey: Key.nudgeDismissCount) }
    static var onboardingPaywallAt: Date? { date(Key.onboardingPaywallAt) }
    static var rideCompletedAt: Date? { date(Key.rideCompletedAt) }

    /// Records a foreground. Returns true when it counts as a new app open.
    @discardableResult
    static func recordForeground(now: Date = Date()) -> Bool {
        if let last = date(Key.lastBackgroundAt), now.timeIntervalSince(last) < reopenGap { return false }
        defaults.set(appOpenCount + 1, forKey: Key.appOpenCount)
        if firstOpenAt == nil { setDate(now, Key.firstOpenAt) }
        return true
    }

    static func recordBackground(now: Date = Date()) { setDate(now, Key.lastBackgroundAt) }
    static func recordNudgeShown(now: Date = Date()) { setDate(now, Key.lastNudgeAt) }
    static func recordNudgeDismissed() { defaults.set(nudgeDismissCount + 1, forKey: Key.nudgeDismissCount) }
    static func recordOnboardingPaywall(now: Date = Date()) { setDate(now, Key.onboardingPaywallAt) }
    static func recordRideCompleted(now: Date = Date()) { setDate(now, Key.rideCompletedAt) }

    // MARK: Home card

    static func isHomeCardSnoozed(now: Date = Date()) -> Bool {
        guard let until = date(Key.homeCardSnoozedUntil) else { return false }
        return now < until
    }

    /// Dismissing during the trial snoozes a day (the countdown is the point); otherwise a week,
    /// and a month once the rider has said no three times.
    static func snoozeHomeCard(inTrial: Bool, now: Date = Date()) {
        let count = defaults.integer(forKey: Key.homeCardDismissCount) + 1
        defaults.set(count, forKey: Key.homeCardDismissCount)
        let days: Double = inTrial ? 1 : (count >= 3 ? 30 : 7)
        setDate(now.addingTimeInterval(days * 86_400), Key.homeCardSnoozedUntil)
    }

    static func reset() { Key.all.forEach(defaults.removeObject(forKey:)) }
}

/// When the app-open nudge may appear. Pure — every input is passed in — so the cadence can be
/// reasoned about (and later tested) without a device clock or UserDefaults.
enum UpsellPolicy {
    struct Inputs {
        var access: MembershipStore.Access
        var now: Date
        var appOpenCount: Int
        var firstOpenAt: Date?
        var lastNudgeAt: Date?
        var nudgeDismissCount: Int
        var onboardingPaywallAt: Date?
        var rideCompletedAt: Date?
    }

    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    static func shouldShowAppOpenNudge(_ i: Inputs, calendar: Calendar = .current) -> Bool {
        // Never right on the heels of the onboarding paywall.
        if let shown = i.onboardingPaywallAt, i.now.timeIntervalSince(shown) < day { return false }

        switch i.access {
        case .pro:
            return false

        case .trial(let endsAt):
            let left = endsAt.timeIntervalSince(i.now)
            if left > 2 * day { return false }                      // day 1: onboarding covered it
            if left > day {                                          // day 2: once, first open of the day
                guard let last = i.lastNudgeAt else { return true }
                return !calendar.isDate(last, inSameDayAs: i.now)
            }
            // Last 24 h: once on entering it, once more inside the last 6 h.
            let lastDayStart = endsAt.addingTimeInterval(-day)
            let finalHoursStart = endsAt.addingTimeInterval(-6 * hour)
            guard let last = i.lastNudgeAt else { return true }
            if last < lastDayStart { return true }
            return i.now >= finalHoursStart && last < finalHoursStart

        case .trialExpired:
            // Nothing works without Pro, so this is the main conversion surface — still capped.
            guard let last = i.lastNudgeAt else { return true }
            return i.now.timeIntervalSince(last) >= 4 * hour

        case .free:
            // No enforced trial: the old, patient cadence with a back-off.
            if i.nudgeDismissCount >= 6 { return false }
            let gap: TimeInterval = i.nudgeDismissCount >= 3 ? 14 * day : 3 * day
            if let last = i.lastNudgeAt, i.now.timeIntervalSince(last) < gap { return false }
            // A just-finished ride is a better moment than an arbitrary third open.
            if let ride = i.rideCompletedAt, ride > (i.lastNudgeAt ?? .distantPast) { return true }
            guard i.appOpenCount >= 3, let first = i.firstOpenAt else { return false }
            return i.now.timeIntervalSince(first) >= 2 * day
        }
    }
}
