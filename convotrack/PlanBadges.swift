import SwiftUI

extension MembershipStore {
    /// The badge for the rider's current access. Free riders with no enforced trial are invited
    /// to Pro the same way as riders whose trial has ended.
    var planBadgeKind: DSPlanBadge.Kind {
        switch access {
        case .pro: .pro
        case .trial: .trial(daysLeft: trialDaysLeft ?? 1)
        case .trialExpired, .free: .goPro
        }
    }

    /// Creating or joining a ride needs Pro (the enforced trial is over). The server enforces
    /// this too; checking here just sends the rider to the paywall without a failed request.
    var mustUpgradeToRide: Bool { access == .trialExpired }
}

/// Plan badge that opens the paywall — except for Pro riders, where it's just a badge.
struct PlanBadgeButton: View {
    let source: PaywallSource
    @EnvironmentObject private var store: MembershipStore
    @EnvironmentObject private var paywall: PaywallPresenter

    var body: some View {
        if store.access == .pro {
            DSPlanBadge(kind: .pro)
        } else {
            Button {
                DSHaptic.selection()
                paywall.present(source)
            } label: {
                DSPlanBadge(kind: store.planBadgeKind)
                    // Small badge, full-size hit target.
                    .frame(minHeight: DS.Target.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(Text("Shows ConvoTrack Pro plans"))
        }
    }
}
