import SwiftUI

/// The compact app-open upsell. It sells the *idea* (countdown + three reasons) and hands off to
/// the full paywall for prices and terms — no purchase button lives here, so the subscription
/// disclosure stays in one place (`MembershipView`).
struct ProNudgeSheet: View {
    /// Called with true for "See plans", false for "Not now". A swipe-down calls nothing; the
    /// presenter's `onDismiss` treats that as "not now".
    let onFinish: (_ wantsPlans: Bool) -> Void

    @EnvironmentObject private var store: MembershipStore
    @Environment(\.dismiss) private var dismiss

    private var headline: LocalizedStringKey {
        switch store.access {
        case .trial:
            guard let days = store.trialDaysLeft, days > 1 else { return "Your free trial ends today" }
            return "days left in your free trial"
        case .trialExpired: return "Your free trial has ended"
        case .pro, .free:   return "Ride bigger with Pro"
        }
    }

    private var subtitle: LocalizedStringKey {
        switch store.access {
        case .trial:        return "After that, creating and joining rides needs Pro."
        case .trialExpired: return "Go Pro to keep creating and joining rides with your crew."
        case .pro, .free:   return "Bigger packs, no monthly ride limit, every ride kept."
        }
    }

    /// "2 days left in your free trial" reads as one sentence to VoiceOver even though the number
    /// is drawn large above it.
    private var headlineText: Text {
        if let bigNumber { return Text("\(bigNumber) ") + Text(headline) }
        return Text(headline)
    }

    /// The big countdown number, only while more than a day is left.
    private var bigNumber: Int? {
        guard case .trial = store.access, let days = store.trialDaysLeft, days > 1 else { return nil }
        return days
    }

    var body: some View {
        VStack(spacing: DS.Space.p5) {
            VStack(spacing: DS.Space.p2) {
                if let bigNumber {
                    Text("\(bigNumber)")
                        .dsText(.heroTitle)
                        .foregroundStyle(DS.Pro.gradient)
                        .accessibilityHidden(true)
                } else {
                    DSIconDisc(systemImage: store.access == .trialExpired ? "lock.fill" : "rosette",
                               size: 56, iconSize: 24, fill: DS.Pro.gold.opacity(0.14), tint: DS.Pro.gold)
                }
                Text(headline)
                    .dsText(.titleLarge)
                    .foregroundStyle(DS.Text.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(headlineText)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: DS.Space.p3) {
                benefit("person.3", "Bring your whole crew — bigger packs")
                benefit("infinity", "No monthly ride limit")
                benefit("calendar", "Every ride kept in your history")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: DS.Space.p2) {
                DSGoProButton(title: "See plans") { finish(wantsPlans: true) }
                DSTextButton(title: "Not now", role: .dismiss) { finish(wantsPlans: false) }
            }
        }
        .padding(.horizontal, DS.Space.screenInset)
        .padding(.top, DS.Space.p6)
        .padding(.bottom, DS.Space.p4)
        .frame(maxWidth: DS.Space.contentMaxWidth)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { DSScreenBackground() }
        .preferredColorScheme(.dark)
    }

    private func benefit(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.p3) {
            DSIconDisc(systemImage: systemImage, size: 32, iconSize: 15, fill: DS.Pro.gold.opacity(0.14), tint: DS.Pro.gold)
            Text(text).dsText(.bodySmall).foregroundStyle(DS.Text.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func finish(wantsPlans: Bool) {
        onFinish(wantsPlans)
        dismiss()
    }
}
