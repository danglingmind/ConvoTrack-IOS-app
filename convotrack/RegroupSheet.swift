import SwiftUI

/// Why a regroup (or emergency) is being called. `.emergency` emits `ride:emergency`; the other
/// three emit `ride:regroup`.
enum RegroupReason: String, CaseIterable {
    case fuel = "Fuel Stop"
    case food = "Food Stop"
    case scenic = "Scenic Stop"
    case emergency = "Emergency"

    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .scenic: return "camera.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        }
    }

    var isEmergency: Bool { self == .emergency }
}

struct RegroupBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// (reason, meters ahead on route to place the meet point)
    ///
    /// There is deliberately no "search for a meet location" path: picking a place off a map
    /// takes long enough that the group has already moved on, which defeats the point of a
    /// regroup. Every regroup now fires the moment a reason is tapped.
    let onBroadcast: (RegroupReason, Double) -> Void
    let isBroadcasting: Bool

    /// How far ahead on the route to place the meet point when broadcasting from the rider's position.
    enum RegroupDistance: CaseIterable {
        case current, ahead100, ahead500
        var meters: Double { switch self { case .current: 0; case .ahead100: 100; case .ahead500: 500 } }
        var label: String  { switch self { case .current: "Current"; case .ahead100: "100 m"; case .ahead500: "500 m" } }
    }

    @Environment(\.verticalSizeClass) private var vSizeClass
    /// Landscape has ~402pt of height and the sheet's portrait content measures ~486pt, so without
    /// adapting it the sheet clamps to full height and pushes the reason tiles — the entire point
    /// of the sheet — below the fold.
    private var isLandscape: Bool { vSizeClass == .compact }

    @State private var selectedReason: RegroupReason? = nil
    @State private var selectedDistance: RegroupDistance = .current
    /// Measured height of the sheet's content, used as its detent so the sheet is exactly as tall
    /// as what it contains. Removing the search field and the broadcast button left a fixed
    /// `.large` detent with a screenful of nothing under the Cancel button.
    @State private var contentHeight: CGFloat = 0

    /// Floor keeps the sheet from collapsing to a sliver on the first frame, before the content
    /// has been measured. SwiftUI clamps the upper end to the screen, and the content stays in a
    /// ScrollView, so a taller-than-screen case (large accessibility text) still scrolls.
    private var sheetHeight: CGFloat { max(contentHeight, 320) }

    /// Tiles broadcast immediately — one tap, no confirmation. That is the whole interaction now.
    private func handleReasonTap(_ reason: RegroupReason) {
        guard !isBroadcasting else { return }
        selectedReason = reason
        onBroadcast(reason, selectedDistance.meters)
    }

    private func dsReason(_ r: RegroupReason) -> DSRegroupReason {
        switch r {
        case .fuel: .fuel
        case .food: .food
        case .scenic: .scenic
        case .emergency: .emergency
        }
    }

    var body: some View {
        // The background is applied AS a background, not as a ZStack sibling. As a sibling its
        // `.ignoresSafeArea()` consumed the safe area for the ScrollView beside it — and the
        // keyboard is reported through the safe area, so SwiftUI's keyboard avoidance had nothing
        // to act on.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The system drag indicator (`.presentationDragIndicator`) sits above this content.
                Color.clear.frame(height: 20)

                HStack(spacing: DS.Space.p3) {
                    Image(systemName: "flag.fill").dsIcon(28, weight: .semibold).foregroundStyle(DS.Accent.base)
                        .accessibilityHidden(true)
                    Text("Regroup").dsText(.titleLarge).foregroundStyle(DS.Text.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.horizontal, DS.Space.screenInset)

                Text("Tap a reason to broadcast instantly")
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.top, isLandscape ? 6 : 12)
                    .padding(.bottom, isLandscape ? 14 : 24)

                // Meet point: offsets the meet point this far ahead on the route.
                VStack(alignment: .leading, spacing: DS.Space.p3) {
                    Text("Meet point").dsText(.fieldLabel).foregroundStyle(DS.Text.secondary)
                    Picker("Meet point", selection: $selectedDistance) {
                        ForEach(RegroupDistance.allCases, id: \.self) { dist in
                            Text(dist.label).tag(dist)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(DS.Accent.base)
                }
                .padding(.horizontal, DS.Space.screenInset)
                .padding(.bottom, isLandscape ? 14 : 24)

                // Reason tiles broadcast on tap, with no confirm. Emergency still emits
                // `ride:emergency` through `onBroadcast` (see the caller).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.p3), count: isLandscape ? 4 : 2), spacing: DS.Space.p3) {
                    ForEach(RegroupReason.allCases, id: \.self) { reason in
                        DSReasonTile(reason: dsReason(reason)) { handleReasonTap(reason) }
                    }
                }
                .padding(.horizontal, DS.Space.screenInset)
                .padding(.bottom, isLandscape ? 14 : 24)

                DSGhostButton(title: "Cancel request") { dismiss() }
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.bottom, isLandscape ? 18 : 28)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded(.up)
            } action: { height in
                contentHeight = height
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Surface.sheet)
        .preferredColorScheme(.dark)
    }
}
