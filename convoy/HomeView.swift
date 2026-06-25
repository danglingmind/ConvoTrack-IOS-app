import SwiftUI
import CoreLocation
import ClerkKit

enum HomeRoute: Hashable {
    case createRide
    case rideLobby
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
@Binding var activeTab: ConvoyBottomNav.Tab
    @Binding var showJoinRide: Bool
    @State private var navPath = NavigationPath()
    @State private var recentRides: [HistoryRide] = []
    @State private var ridesLoaded = false
    @State private var selectedRide: HistoryRide? = nil
    @State private var showRideSummary = false

    var body: some View {
        NavigationStack(path: $navPath) {
            homeRoot
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .createRide:
                        CreateRideView()
                    case .rideLobby:
                        RideLobbyView()
                    }
                }
                .navigationDestination(isPresented: $showRideSummary) {
                    if let ride = selectedRide {
                        RideSummaryView(rideId: ride.rideId, rideTitle: ride.title, fallback: ride)
                    }
                }
                .task {
                    recentRides = (try? await APIClient.shared.getMyRides()) ?? []
                    ridesLoaded = true
                }
        }
        .onChange(of: appState.currentRideId) { _, newId in
            guard newId != nil else { return }
            navPath = NavigationPath([HomeRoute.rideLobby])
        }
        .onChange(of: appState.popToRoot) { _, shouldPop in
            if shouldPop {
                navPath = NavigationPath()
                appState.popToRoot = false
            }
        }
    }

    private var homeRoot: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72)


                    VStack(spacing: 32) {
                        // Action Grid
                        HStack(spacing: 12) {
                            Button(action: { navPath.append(HomeRoute.createRide) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                                    Text("CREATE RIDE").font(.labelCaps).tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.primaryFixed)
                                .foregroundColor(Color.onPrimaryFixed)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Button(action: { showJoinRide = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.badge.plus").font(.system(size: 20))
                                    Text("JOIN RIDE").font(.labelCaps).tracking(1)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.surfaceContainerHighest)
                                .foregroundColor(Color.onSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 20)

                        // Active Ride Section — only when a ride is in progress
                        if appState.currentRideId != nil {
                            ActiveRideSection(
                                ride: appState.currentRide,
                                rideId: appState.currentRideId,
                                onTap: { navPath.append(HomeRoute.rideLobby) },
                                onRideLoaded: { ride in appState.currentRide = ride },
                                onRideClear: { appState.currentRideId = nil }
                            )
                        }

                        // Recent Rides
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("RECENT RIDES").font(.headlineMd).foregroundColor(Color.onSurface)
                                Spacer()
                                Button(action: { activeTab = .flagged }) {
                                    Text("VIEW ALL").font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                                }
                            }
                            .padding(.horizontal, 20)

                            if !ridesLoaded {
                                ProgressView()
                                    .tint(Color.primaryFixed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else if recentRides.isEmpty {
                                Text("No rides yet")
                                    .font(.bodyMd)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(Array(recentRides.prefix(3))) { ride in
                                        Button(action: { handleRecentRideTap(ride) }) {
                                            RecentRideRow(icon: "road.lanes", title: ride.title, subtitle: rideSubtitle(ride))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        Color.clear.frame(height: 100)
                    }
                }
            }
            .refreshable {
                async let rides = APIClient.shared.getMyRides()
                recentRides = (try? await rides) ?? recentRides
            }
            .ignoresSafeArea(edges: .bottom)

            HStack {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primaryFixed)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Helpers

    private func handleRecentRideTap(_ ride: HistoryRide) {
        if ride.status == "COMPLETED" {
            selectedRide = ride
            showRideSummary = true
        } else {
            appState.currentRideId = ride.rideId
            if let code = ride.inviteCode { appState.inviteCode = code }
            navPath = NavigationPath([HomeRoute.rideLobby])
        }
    }

    private func rideSubtitle(_ ride: HistoryRide) -> String {
        var parts: [String] = []
        if let raw = ride.endedAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: raw) {
                let df = DateFormatter()
                df.dateFormat = "dd MMM"
                parts.append(df.string(from: date).uppercased())
            }
        }
        parts.append(String(format: "%.0f KM", ride.distanceMeters / 1000))
        if let secs = ride.durationSeconds {
            let h = secs / 3600; let m = (secs % 3600) / 60
            parts.append(String(format: "%d:%02d HRS", h, m))
        }
        return parts.joined(separator: " · ")
    }



}

// MARK: - Active Ride Section

struct ActiveRideSection: View {
    let ride: Ride?
    let rideId: String?
    let onTap: () -> Void
    let onRideLoaded: (Ride) -> Void
    let onRideClear: () -> Void

    private var statusLabel: String {
        switch ride?.status {
        case "ACTIVE": return "LIVE NOW"
        case "LOBBY":  return "IN LOBBY"
        default:       return "ACTIVE"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ACTIVE RIDE")
                    .font(.headlineMd).foregroundColor(Color.onSurface)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.primaryFixed).frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                }
            }
            .padding(.horizontal, 20)

            Button(action: onTap) {
                ActiveRideCard(ride: ride)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .task {
            guard ride == nil, let id = rideId else { return }
            guard let loaded = try? await APIClient.shared.getRide(id) else {
                // 404 or network failure — clear stale ID
                onRideClear()
                return
            }
            if loaded.status == "COMPLETED" || loaded.status == "ENDED" {
                onRideClear()
            } else {
                onRideLoaded(loaded)
            }
        }
    }
}

struct ActiveRideCard: View {
    let ride: Ride?

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraCommand: MapCameraCommand? = nil

    private var participantCount: Int { ride?.participants.count ?? 0 }
    private var rideStatus: String {
        guard let s = ride?.status else { return "LOBBY" }
        return s == "IN_PROGRESS" ? "RIDING" : s
    }

    var body: some View {
        ZStack {
            // Map background
            if let ride, !ride.waypoints.isEmpty {
                let destPin = MapPin(
                    id: "dest",
                    coordinate: CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng),
                    style: .simpleDot(color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1), size: 10),
                    anchorBottom: false
                )
                GoogleMapView(
                    routeCoords:   routeCoordinates,
                    pins:          [destPin],
                    cameraCommand: cameraCommand,
                    isInteractive: false
                )
                .task(id: ride.id) { await computeRoute(ride) }
            } else {
                LinearGradient(
                    colors: [Color.surfaceContainerHigh, Color.surfaceDim],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }

            // Scrim: subtle at top, heavy at bottom for text legibility
            LinearGradient(
                colors: [
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Destination chip
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color.primaryFixed)
                        Text(ride?.destinationName ?? "Loading…")
                            .font(.labelCaps)
                            .foregroundColor(.white)
                            .tracking(1)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    Spacer()
                }

                Spacer()

                // Bottom row
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ride?.title ?? "Loading…")
                            .font(.headlineMd)
                            .foregroundColor(.white)
                        HStack(spacing: 8) {
                            HStack(spacing: -6) {
                                ForEach(0..<max(1, min(participantCount, 3)), id: \.self) { _ in
                                    Circle()
                                        .fill(Color.surfaceVariant)
                                        .frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                                }
                            }
                            Text("\(participantCount) Rider\(participantCount == 1 ? "" : "s") · \(rideStatus)")
                                .font(.dataMono)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    Text("RESUME")
                        .font(.labelCaps)
                        .foregroundColor(Color.onPrimaryFixed)
                        .tracking(1)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.primaryFixed)
                        .clipShape(Capsule())
                        .shadow(color: Color.primaryFixed.opacity(0.5), radius: 10)
                }
            }
            .padding(16)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primaryFixed.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    @MainActor
    private func computeRoute(_ ride: Ride) async {
        let sorted = ride.waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }

        var allCoords: [CLLocationCoordinate2D] = []
        for i in 0..<sorted.count - 1 {
            let origin = CLLocationCoordinate2D(latitude: sorted[i].lat,     longitude: sorted[i].lng)
            let dest   = CLLocationCoordinate2D(latitude: sorted[i+1].lat,   longitude: sorted[i+1].lng)
            if let result = try? await GoogleDirectionsService.route(from: origin, to: dest) {
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
            }
        }

        routeCoordinates = allCoords
        if !allCoords.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 48)
        }
    }
}

// MARK: - Recent Ride Row

struct RecentRideRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.surfaceVariant).frame(width: 56, height: 56)
                Image(systemName: icon).font(.system(size: 22)).foregroundColor(Color.primaryFixed)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.bodyLg).foregroundColor(Color.onSurface).fontWeight(.bold)
                Text(subtitle).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(Color.onSurfaceVariant)
        }
        .padding(16)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    HomeView(activeTab: .constant(.track), showJoinRide: .constant(false))
        .environmentObject(AppState())
}
