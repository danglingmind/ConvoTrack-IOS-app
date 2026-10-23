import SwiftUI

/// Max riders stepper with the plan's limit under it. Lives in the ride planner's
/// sheet.
struct RiderLimitSection: View {
    @Binding var maxRiders: Int
    let riderCap: Int
    let isPremium: Bool
    var onUpgrade: () -> Void

    private var atRiderCap: Bool { maxRiders >= riderCap && !isPremium }

    /// The limit is always visible, not only once the rider walks into it. Free riders get a quiet
    /// way into the paywall; Pro riders just see what their plan allows.
    @ViewBuilder private var riderPlanLine: some View {
        if isPremium {
            Label { Text("Pro · up to \(riderCap) riders") } icon: { Image(systemName: "rosette") }
                .dsText(.helper)
                .foregroundStyle(DS.Text.muted)
        } else {
            Button(action: onUpgrade) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").dsIcon(11, weight: .semibold)
                    Text("Up to \(riderCap) riders on your plan").foregroundStyle(DS.Text.muted)
                    Text("Bigger packs with Pro").foregroundStyle(DS.Pro.gradient)
                }
                .dsText(.helper)
                .frame(minHeight: DS.Target.minimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Text.muted)
            .accessibilityHint(Text("Shows ConvoTrack Pro plans"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p3) {
            DSStepperRow(
                title: "Max riders",
                value: maxRiders,
                onIncrement: {
                    if maxRiders < riderCap {
                        maxRiders += 1
                    } else if !isPremium {
                        onUpgrade()
                    }
                },
                onDecrement: { if maxRiders > 2 { maxRiders -= 1 } }
            )
            if atRiderCap {
                DSPromoBanner(eyebrow: "ConvoTrack Pro", message: "Pro unlocks bigger packs", actionTitle: "Go Pro", goProStyle: true, action: onUpgrade)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                riderPlanLine
            }
        }
        .dsAnimation(.spring(response: 0.3, dampingFraction: 0.8), value: atRiderCap)
    }
}
