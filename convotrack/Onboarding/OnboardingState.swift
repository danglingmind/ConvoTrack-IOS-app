import Foundation

/// How big the rider says their usual group is. Only ever used to prefill a new ride's
/// rider count and to decide whether the paywall headline can honestly talk about the
/// free-plan rider cap.
enum PackSize: String, CaseIterable, Identifiable {
    case duo, small, medium, large, unsure

    var id: String { rawValue }

    /// Rider count to prefill in CreateRide. nil = no opinion, keep the default.
    var suggestedMaxRiders: Int? {
        switch self {
        case .duo:    return 2
        case .small:  return 5
        case .medium: return 12
        case .large:  return 20
        case .unsure: return nil
        }
    }

    /// True when this answer is bigger than the free plan's rider cap, so a paywall
    /// headline about the cap is relevant rather than invented.
    func exceedsFreeCap(_ cap: Int) -> Bool {
        guard let n = suggestedMaxRiders else { return false }
        return n > cap
    }
}

/// Onboarding bookkeeping. Plain UserDefaults: nothing here is secret, and losing it only
/// means a returning rider sees the intro once more.
enum OnboardingState {
    /// Bump to re-run onboarding for everyone (or to A/B a new flow).
    static let currentVersion = 1

    private static let completedVersionKey = "onboarding.completedVersion"
    private static let packSizeKey         = "onboarding.packSize"
    private static let packSizeAppliedKey  = "onboarding.packSizeApplied"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.integer(forKey: completedVersionKey) >= currentVersion }
        set { UserDefaults.standard.set(newValue ? currentVersion : 0, forKey: completedVersionKey) }
    }

    static var packSize: PackSize? {
        get { UserDefaults.standard.string(forKey: packSizeKey).flatMap(PackSize.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: packSizeKey) }
    }

    /// Returns the prefill for the first ride a rider creates, then never again — later rides
    /// start from the normal default rather than being forced back to the onboarding answer.
    static func consumeSuggestedMaxRiders() -> Int? {
        guard !UserDefaults.standard.bool(forKey: packSizeAppliedKey),
              let n = packSize?.suggestedMaxRiders else { return nil }
        UserDefaults.standard.set(true, forKey: packSizeAppliedKey)
        return n
    }
}
