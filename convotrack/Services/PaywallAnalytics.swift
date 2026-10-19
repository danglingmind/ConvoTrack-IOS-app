import Foundation

/// Upsell funnel events (`POST /events`): which surface opened the paywall and whether the rider
/// bought. Batched for a couple of seconds; a failed batch is kept and goes out with the next one
/// (in memory only — a lost funnel event must never cost the rider anything, so no disk queue).
@MainActor
enum PaywallAnalytics {
    enum Event: String {
        case paywallShown = "paywall_shown"
        case purchaseStarted = "paywall_purchase_started"
        case converted = "paywall_converted"
        case paywallDismissed = "paywall_dismissed"
        case nudgeShown = "nudge_shown"
        case nudgeDismissed = "nudge_dismissed"
        case homeCardDismissed = "home_card_dismissed"
    }

    private static var pending: [PaywallEventPayload] = []
    private static var flushTask: Task<Void, Never>?

    static func log(_ event: Event, source: PaywallSource? = nil, access: MembershipStore.Access? = nil) {
        pending.append(PaywallEventPayload(
            name: event.rawValue,
            source: source?.rawValue,
            access: access.map(accessName),
            occurredAt: ISO8601DateFormatter().string(from: Date())
        ))
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private static func flush() async {
        let batch = Array(pending.prefix(50))
        guard !batch.isEmpty else { return }
        pending.removeFirst(batch.count)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        do {
            try await APIClient.shared.sendEvents(PaywallEventsRequest(platform: "ios", appVersion: version, events: batch))
        } catch {
            // Keep it for the next flush, capped so an offline rider can't grow it without bound.
            pending.insert(contentsOf: batch, at: 0)
            if pending.count > 200 { pending.removeLast(pending.count - 200) }
            return
        }
        if !pending.isEmpty { await flush() }
    }

    private static func accessName(_ access: MembershipStore.Access) -> String {
        switch access {
        case .pro: "pro"
        case .trial: "trial"
        case .trialExpired: "trialExpired"
        case .free: "free"
        }
    }
}
