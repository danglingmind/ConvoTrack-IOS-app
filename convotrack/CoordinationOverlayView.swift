import SwiftUI
import CoreLocation

struct CoordinationOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showGroupSplitAlert = true
    @State private var showRegroupSheet = false
    @State private var broadcasting = false

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

    var body: some View {
        ZStack {
            // Map background
            AsyncImage(url: URL(string: "https://lh3.googleusercontent.com/aida-public/AB6AXuDyzcFRx4psTj0PeoTPwu9qtRTBHP1dwvjvwlAwwvVi5QEhGD7qYmLeOdewLYaWHkPb5Mjmd9wCLmXZQQYIgJdxLGihCZWuqVtxlMZReZQK0mWEaqPrdiqaZjdoE1z513qujZTk6oAkK7m6_EXaGfWhdqGZoSc0XBQRHDE9erqm_7TrUgqOtqq_kdSdxk8Jtzmpqud3DTXUpWft8ZtYBXNHh6WjWPjeoFw5ECd5PfEKofqKLg4XiYVmMvjYNA4njyF1CJ6VbL1x8UE")) { image in
                image.resizable().scaledToFill()
                    .grayscale(0.4).opacity(0.4).contrast(1.25)
            } placeholder: {
                DS.Background.base
            }
            .ignoresSafeArea()

            // Gradient overlay
            LinearGradient(
                colors: [DS.Background.base.opacity(0.6), .clear, DS.Background.base.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top App Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .foregroundColor(DS.Accent.base)
                            .frame(width: 44, height: 44)
                            .background(DS.Surface.card.base.opacity(0.7))
                            .clipShape(Circle())
                    }
                    Text("CONVOTRACK")
                        .dsText(.heroTitleCompact)
                        .foregroundColor(DS.Accent.base)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Status pill
                HStack(spacing: 8) {
                    Text("Squad Status").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(DS.Text.secondary.base).tracking(1)
                    Text("6 ACTIVE • 1 BEHIND").dsText(.dataMono).foregroundColor(DS.Accent.base)
                    Rectangle().frame(width: 1, height: 16).foregroundColor(DS.Border.strongColor.opacity(0.3))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Accent.base)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.Surface.raised.opacity(0.7))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Border.strongColor.opacity(0.3), lineWidth: 1))
                .padding(.top, 12)

                // Telemetry widgets
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        HUDWidget(label: "SPEED", value: "88", unit: "KM/H")
                        HUDWidget(label: "POS", value: "02", unit: "OF 06", isSecondary: true)
                    }
                    .padding(.trailing, 20)
                }

                Spacer()

                // Group Split Alert
                if showGroupSplitAlert {
                    GroupSplitAlert(
                        riderName: "Ravi",
                        gapMeters: 2400,
                        onIgnore: {
                            withAnimation(.spring()) { showGroupSplitAlert = false }
                        },
                        onRegroup: {
                            showRegroupSheet = true
                        }
                    )
                    .padding(.horizontal, 20)
                    .transition(.scale.combined(with: .opacity))
                }

                Spacer()

            }

            // Bottom Nav
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    NavTabItem(icon: "house.and.flag", label: "FLAGGED", isActive: false) {}
                    Spacer()
                    NavTabItem(icon: "location.north.fill", label: "TRACK", isActive: true) {}
                    Spacer()
                    NavTabItem(icon: "person", label: "PROFILE", isActive: false) {}
                }
                .padding(.horizontal, 32)
                .frame(height: 80)
                .background(DS.Background.deep.opacity(0.95))
                .overlay(Rectangle().frame(height: 1).foregroundColor(DS.Border.strongColor.opacity(0.3)), alignment: .top)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showRegroupSheet) {
            RegroupBottomSheet(
                onBroadcast: { _, _ in
                    broadcasting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showRegroupSheet = false
                        withAnimation { showGroupSplitAlert = false }
                        broadcasting = false
                    }
                },
                isBroadcasting: broadcasting
            )
        }
        .preferredColorScheme(.dark)
    }
}

struct HUDWidget: View {
    let label: String
    let value: String
    let unit: String
    var isSecondary: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label).dsText(.badge).foregroundColor(DS.Text.secondary.base).tracking(1)
            Text(value)
                .dsText(.titleLarge)
                .foregroundColor(isSecondary ? DS.Text.secondary.base : DS.Accent.base)
            Text(unit).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(DS.Text.secondary.base).tracking(1)
        }
        .frame(width: 96)
        .padding(12)
        .background(
            LinearGradient(colors: [DS.Surface.raised, DS.Surface.card.base], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.Border.strongColor, lineWidth: 1))
    }
}

struct GroupSplitAlert: View {
    let riderName: String
    let gapMeters: Double
    let onIgnore: () -> Void
    let onRegroup: () -> Void

    /// Whole metres under a kilometre, tenths of a km above, rounded the way the turn banner is so
    /// the figure doesn't tick on every GPS fix.
    private var gapText: String {
        if gapMeters < 1000 { return "\(max(10, Int((gapMeters / 10).rounded()) * 10)) m" }
        return String(format: "%.1f km", gapMeters / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.p4) {
            HStack(spacing: DS.Space.p3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .dsIcon(DS.IconSize.lg, weight: .semibold)
                    .foregroundStyle(DS.Surface.dangerContainer)
                    .frame(width: 44, height: 44)
                    .background(DS.Status.danger, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text("Group split")
                    .dsText(.titleLarge)
                    .foregroundStyle(DS.Status.danger)
                    .accessibilityAddTraits(.isHeader)
            }

            Text("**\(riderName)** is **\(gapText)** behind the leader.")
                .dsText(.body)
                .foregroundStyle(DS.Text.primary)

            // Regroup is the action; Dismiss is a quiet text button.
            DSAdaptiveStack(spacing: DS.Space.p3) {
                DSPillButton(title: "Regroup", systemImage: "person.3.fill", variant: .primary, large: true, action: onRegroup)
                DSTextButton(title: "Dismiss", role: .dismiss, action: onIgnore)
            }
        }
        .padding(DS.Space.p5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Status.dangerBorder, lineWidth: DS.BorderWidth.emphasis))
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(String(localized: "Group split. \(riderName) is \(gapText) behind the leader")).post()
            DSHaptic.alert()
        }
    }
}

struct RegroupBottomSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// (reason, meters ahead on route to place the meet point)
    ///
    /// There is deliberately no "search for a meet location" path: picking a place off a map
    /// takes long enough that the group has already moved on, which defeats the point of a
    /// regroup. Every regroup now fires the moment a reason is tapped.
    let onBroadcast: (CoordinationOverlayView.RegroupReason, Double) -> Void
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

    @State private var selectedReason: CoordinationOverlayView.RegroupReason? = nil
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
    private func handleReasonTap(_ reason: CoordinationOverlayView.RegroupReason) {
        guard !isBroadcasting else { return }
        selectedReason = reason
        onBroadcast(reason, selectedDistance.meters)
    }

    private func dsReason(_ r: CoordinationOverlayView.RegroupReason) -> DSRegroupReason {
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
                    ForEach(CoordinationOverlayView.RegroupReason.allCases, id: \.self) { reason in
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

struct NavTabItem: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isActive {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 20))
                    Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                }
                .foregroundColor(DS.Text.onAccent)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(DS.Accent.base)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: DS.Accent.base.opacity(0.3), radius: 8)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 22))
                    Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                }
                .foregroundColor(DS.Text.secondary.base.opacity(0.6))
            }
        }
    }
}

#Preview {
    CoordinationOverlayView()
}
