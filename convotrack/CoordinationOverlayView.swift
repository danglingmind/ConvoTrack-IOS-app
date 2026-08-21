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
                Color.surfaceDim
            }
            .ignoresSafeArea()

            // Gradient overlay
            LinearGradient(
                colors: [Color.surfaceDim.opacity(0.6), .clear, Color.surfaceDim.opacity(0.6)],
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
                            .foregroundColor(Color.primaryFixed)
                            .frame(width: 44, height: 44)
                            .background(Color.surfaceContainer.opacity(0.7))
                            .clipShape(Circle())
                    }
                    Text("CONVOTRACK")
                        .font(.headlineLg)
                        .foregroundColor(Color.primaryFixed)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Status pill
                HStack(spacing: 8) {
                    Text("Squad Status").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
                    Text("6 ACTIVE • 1 BEHIND").font(.dataMono).foregroundColor(Color.primaryFixed)
                    Rectangle().frame(width: 1, height: 16).foregroundColor(Color.outlineVariant.opacity(0.3))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color.primaryFixed)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.surfaceContainerHigh.opacity(0.7))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
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
                .background(Color.surfaceContainerLowest.opacity(0.95))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.outlineVariant.opacity(0.3)), alignment: .top)
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
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            Text(value)
                .font(.headlineMd)
                .foregroundColor(isSecondary ? Color.secondary : Color.primaryFixed)
            Text(unit).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
        }
        .frame(width: 96)
        .padding(12)
        .background(
            LinearGradient(colors: [Color(hex: "1c1c1c"), Color(hex: "111111")], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "333333"), lineWidth: 1))
    }
}

struct GroupSplitAlert: View {
    let onIgnore: () -> Void
    let onRegroup: () -> Void

    var body: some View {
        ZStack {
            // Dot texture
            Color.errorContainer.opacity(0.1)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.onPrimaryFixed)
                        .frame(width: 44, height: 44)
                        .background(Color.errorColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("GROUP SPLIT")
                        .font(.headlineMd)
                        .foregroundColor(Color.errorColor)
                        .tracking(-0.5)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Last rider is")
                        Text("2.4 km behind").foregroundColor(Color.errorColor).fontWeight(.bold)
                        Text(".")
                    }
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurface)
                    Text("Signal strength dropping rapidly.")
                        .font(.bodyMd)
                        .foregroundColor(Color.onSurface)
                }

                HStack(spacing: 12) {
                    Button(action: onIgnore) {
                        Text("Ignore")
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurface)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.surfaceContainerHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline, lineWidth: 1))
                    }
                    Button(action: onRegroup) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill").font(.system(size: 14))
                            Text("Regroup").font(.labelCaps).tracking(1)
                        }
                        .foregroundColor(Color.onPrimaryFixed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.errorColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor, lineWidth: 2))
        .shadow(color: Color.errorContainer.opacity(0.3), radius: 12)
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

    var body: some View {
        // The background is applied AS a background, not as a ZStack sibling. As a sibling its
        // `.ignoresSafeArea()` consumed the safe area for the ScrollView beside it — and the
        // keyboard is reported through the safe area, so SwiftUI's keyboard avoidance had nothing
        // to act on and the search field sat underneath the keyboard.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // No hand-drawn grabber here: `.presentationDragIndicator(.visible)` already
                    // draws the system one, and having both showed two stacked bars at the top.
                    // The system indicator sits in the sheet's own chrome above this content, so
                    // only top padding is needed to clear it.
                    Color.clear.frame(height: 20)

                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: "flag.fill").font(.system(size: 32)).foregroundColor(Color.primaryFixed)
                            Text("REGROUP").font(.headlineLg).foregroundColor(Color.primaryFixed)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    Text("Tap a reason to broadcast instantly")
                        .font(.bodyLg)
                        .foregroundColor(Color.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, isLandscape ? 6 : 12)
                        .padding(.bottom, isLandscape ? 14 : 24)

                    // Distance selector — offsets the meet point this far ahead on the route.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MEET POINT")
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant)
                            .tracking(2)

                        HStack(spacing: 0) {
                            ForEach(RegroupDistance.allCases, id: \.self) { dist in
                                Button(action: { selectedDistance = dist }) {
                                    Text(dist.label)
                                        .font(.toggleLabel)
                                        .foregroundColor(selectedDistance == dist ? Color.onPrimaryFixed : Color.onSurfaceVariant)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(selectedDistance == dist ? Color.primaryFixed : Color.clear)
                                }
                            }
                        }
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isLandscape ? 14 : 24)

                    // Reason Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: isLandscape ? 4 : 2), spacing: 12) {
                        ForEach(CoordinationOverlayView.RegroupReason.allCases, id: \.self) { reason in
                            Button(action: { handleReasonTap(reason) }) {
                                VStack(spacing: 10) {
                                    Image(systemName: reason.icon)
                                        .font(.system(size: 28))
                                        .foregroundColor(reason.isEmergency ? Color.errorColor : Color.primaryFixed)
                                    Text(reason.rawValue)
                                        .font(.labelCaps)
                                        .foregroundColor(reason.isEmergency ? Color.errorColor : Color.onSurface)
                                        .tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(isLandscape ? 14 : 20)
                                .background(
                                    reason.isEmergency
                                    ? Color.errorContainer.opacity(0.1)
                                    : Color(hex: "1c1c1c")
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            selectedReason == reason
                                            ? Color.primaryFixed
                                            : (reason.isEmergency ? Color.errorColor.opacity(0.4) : Color.outlineVariant.opacity(0.3)),
                                            lineWidth: selectedReason == reason ? 2 : 1
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isLandscape ? 14 : 24)

                    Button(action: { dismiss() }) {
                        Text("Cancel Request")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onSurfaceVariant)
                            .tracking(8)
                    }
                    .padding(.top, isLandscape ? 10 : 16)
                    .padding(.bottom, isLandscape ? 18 : 40)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height.rounded(.up)
                } action: { height in
                    contentHeight = height
                }
            }
            .background(Color.surfaceDim.ignoresSafeArea())
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
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
                .foregroundColor(Color.onPrimaryFixed)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Color.primaryFixed)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.primaryFixed.opacity(0.3), radius: 8)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 22))
                    Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                }
                .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
            }
        }
    }
}

#Preview {
    CoordinationOverlayView()
}
