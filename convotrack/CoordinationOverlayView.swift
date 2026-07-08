import SwiftUI
import CoreLocation

struct CoordinationOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showGroupSplitAlert = true
    @State private var showRegroupSheet = false
    @State private var selectedReason: RegroupReason? = nil
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
                selectedReason: $selectedReason,
                onBroadcast: { _ in
                    broadcasting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showRegroupSheet = false
                        withAnimation { showGroupSplitAlert = false }
                        broadcasting = false
                    }
                },
                isBroadcasting: broadcasting
            )
            .presentationDetents([.large])
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
    @Binding var selectedReason: CoordinationOverlayView.RegroupReason?
    let onBroadcast: (CLLocationCoordinate2D?) -> Void
    let isBroadcasting: Bool

    private enum LocationMode { case myPosition, searchedLocation }

    @State private var locationMode: LocationMode = .myPosition
    @State private var locationQuery = ""
    @State private var locationResults: [PlaceResult] = []
    @State private var pickedLocation: (name: String, coordinate: CLLocationCoordinate2D)? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    private var broadcastBlocked: Bool {
        isBroadcasting || selectedReason == nil || (locationMode == .searchedLocation && pickedLocation == nil)
    }

    var body: some View {
        ZStack {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.outlineVariant.opacity(0.4))
                        .frame(width: 64, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: "flag.fill").font(.system(size: 32)).foregroundColor(Color.primaryFixed)
                            Text("REGROUP").font(.headlineLg).foregroundColor(Color.primaryFixed)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    Text("Select a reason for the broadcast:")
                        .font(.bodyLg)
                        .foregroundColor(Color.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    // Reason Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(CoordinationOverlayView.RegroupReason.allCases, id: \.self) { reason in
                            Button(action: { selectedReason = reason }) {
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
                                .padding(20)
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
                    .padding(.bottom, 24)

                    // Location Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MEET LOCATION")
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant)
                            .tracking(2)

                        // Mode toggle
                        HStack(spacing: 0) {
                            Button(action: {
                                searchTask?.cancel()
                                locationMode = .myPosition
                                pickedLocation = nil
                                locationQuery = ""
                                locationResults = []
                            }) {
                                Text("My Position")
                                    .font(.toggleLabel)
                                    .foregroundColor(locationMode == .myPosition ? Color.onPrimaryFixed : Color.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(locationMode == .myPosition ? Color.primaryFixed : Color.clear)
                            }
                            Button(action: { locationMode = .searchedLocation }) {
                                Text("Search Location")
                                    .font(.toggleLabel)
                                    .foregroundColor(locationMode == .searchedLocation ? Color.onPrimaryFixed : Color.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(locationMode == .searchedLocation ? Color.primaryFixed : Color.clear)
                            }
                        }
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        if locationMode == .searchedLocation {
                            if let picked = pickedLocation {
                                // Confirmed location chip
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(Color.primaryFixed)
                                        .font(.system(size: 16))
                                    Text(picked.name)
                                        .font(.bodyMd)
                                        .foregroundColor(Color.onSurface)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        pickedLocation = nil
                                        locationQuery = ""
                                        locationResults = []
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.surfaceContainerHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryFixed.opacity(0.4), lineWidth: 1))
                            } else {
                                // Search field
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(Color.outline.opacity(0.6))
                                            .font(.system(size: 16))
                                            .padding(.leading, 16)
                                        TextField("Search for a meet location...", text: $locationQuery)
                                            .font(.bodyMd)
                                            .foregroundColor(Color.onSurface)
                                            .tint(Color.primaryFixed)
                                            .padding(.leading, 12)
                                            .padding(.trailing, 16)
                                            .frame(height: 48)
                                            .onChange(of: locationQuery) { _, newValue in
                                                searchTask?.cancel()
                                                guard newValue.count >= 2 else { locationResults = []; return }
                                                searchTask = Task {
                                                    try? await Task.sleep(for: .milliseconds(300))
                                                    guard !Task.isCancelled else { return }
                                                    await performLocationSearch(newValue)
                                                }
                                            }
                                    }
                                    .background(Color.surfaceContainerHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))

                                    if !locationResults.isEmpty {
                                        locationSearchResults
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Broadcast Button
                    Button(action: {
                        onBroadcast(locationMode == .myPosition ? nil : pickedLocation?.coordinate)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: isBroadcasting ? "arrow.clockwise" : "dot.radiowaves.left.and.right")
                                .font(.system(size: 24))
                            Text(isBroadcasting ? "TRANSMITTING..." : "Broadcast Regroup")
                                .font(.headlineMd)
                        }
                        .modifier(LimePrimaryButton())
                        .frame(height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.primaryFixed.opacity(0.4), radius: 20)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal, 20)
                    .disabled(broadcastBlocked)
                    .opacity(broadcastBlocked ? 0.5 : 1)

                    Button(action: { dismiss() }) {
                        Text("Cancel Request")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onSurfaceVariant)
                            .tracking(8)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var locationSearchResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(locationResults.prefix(4).enumerated()), id: \.offset) { index, item in
                Button(action: {
                    pickedLocation = (name: item.name, coordinate: item.coordinate)
                    locationQuery = item.name
                    locationResults = []
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Color.primaryFixed)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurface)
                                .lineLimit(1)
                            if let addr = item.formattedAddress, !addr.isEmpty {
                                Text(addr)
                                    .font(.captionMd)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let userLoc = LocationService.shared.lastLocation {
                            let dist = userLoc.distance(from: item.location)
                            Text(dist < 1000 ? "\(Int(dist)) m" : String(format: "%.1f km", dist / 1000))
                                .font(.dataMono)
                                .foregroundColor(Color.onSurfaceVariant)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if index < min(locationResults.count, 4) - 1 {
                    Divider().background(Color.outline.opacity(0.2)).padding(.leading, 44)
                }
            }
        }
        .background(Color.surfaceContainerHighest)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
        .padding(.top, 4)
    }

    @MainActor
    private func performLocationSearch(_ query: String) async {
        let results = await GooglePlacesService.search(query: query, near: LocationService.shared.lastLocation)
        guard !Task.isCancelled else { return }
        locationResults = results
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
