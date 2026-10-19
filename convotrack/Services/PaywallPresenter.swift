import Combine
import Foundation

/// Where a paywall was opened from. Picks the paywall's headline, and later tells us which
/// surfaces actually convert.
enum PaywallSource: String {
    case appOpen, homeCard, homeBadge
    case createBlocked, joinBlocked
    case riderCap, quotaExceeded, rideSummary, profile
}

/// One paywall presentation. Carrying the source in the presented item (rather than a separate
/// `@State` read inside the sheet closure) means the sheet always gets the source that opened it.
struct PaywallRequest: Identifiable {
    let id = UUID()
    let source: PaywallSource
}

/// The app's single paywall entry point. Owned by `MainTabView`, which presents the sheet; any
/// screen below it calls `present(_:)` instead of keeping its own `showMembership` sheet.
@MainActor
final class PaywallPresenter: ObservableObject {
    @Published var request: PaywallRequest?

    func present(_ source: PaywallSource) {
        // One paywall at a time; a second tap while one is up is a no-op.
        guard request == nil else { return }
        request = PaywallRequest(source: source)
    }
}
