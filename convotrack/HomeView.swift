import SwiftUI
import CoreLocation
import ClerkKit

enum HomeRoute: Hashable {
    case createRide
    case rideLobby
}

enum NearbyLoadState {
    case loading, loaded, locationDenied, error
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(Clerk.self) private var clerk
    @Binding var activeTab: ConvoTrackBottomNav.Tab
    @Binding var showJoinRide: Bool
    @State private var navPath = NavigationPath()
    @State private var nearbyRides: [NearbyRide] = []
    @State private var nearbyState: NearbyLoadState = .loading
    @State private var selectedNearbyRide: NearbyRide? = nil
    @State private var recentRides: [HistoryRide] = []
    @State private var recentLoading = true
    @State private var selectedHistoryRide: HistoryRide? = nil

    // Nearby Rides discovery is temporarily hidden on the client. Backend support
    // stays fully intact — flip this to `true` to re-enable the entire section.
    private let showNearbyRides = false

    var body: some View {
        NavigationStack(path: $navPath) {
            homeRoot
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .createRide: CreateRideView()
                    case .rideLobby:  RideLobbyView()
                    }
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

            VStack(spacing: 0) {
                Color.clear.frame(height: 72)

                // Fixed section
                VStack(spacing: 32) {
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { navPath.append(HomeRoute.createRide) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 20))
                                Text("CREATE RIDE").font(.labelCaps).tracking(1)
                            }
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color.primaryFixed)
                            .foregroundColor(Color.onPrimaryFixed)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button(action: { showJoinRide = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus").font(.system(size: 20))
                                Text("JOIN RIDE").font(.labelCaps).tracking(1)
                            }
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(Color.surfaceContainerHighest)
                            .foregroundColor(Color.onSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)

                    // Active ride card
                    if appState.currentRideId != nil {
                        ActiveRideSection(
                            ride: appState.currentRide,
                            rideId: appState.currentRideId,
                            onTap: { navPath.append(HomeRoute.rideLobby) },
                            onRideLoaded: { appState.currentRide = $0 },
                            onRideClear:  { appState.currentRideId = nil }
                        )
                    }

                    // Nearby Rides header
                    if showNearbyRides {
                        HStack {
                            Text("NEARBY RIDES").font(.headlineMd).foregroundColor(Color.onSurface)
                            Spacer()
                            Button(action: { Task { await loadNearby() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.primaryFixed)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 16)

                if showNearbyRides {
                    // Scrollable nearby rides list
                    ScrollView {
                        VStack(spacing: 12) {
                            nearbyContent
                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 20)
                    }
                    .refreshable { await loadNearby() }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    recentRidesSection
                }
            }

            // Floating top bar
            HStack {
                Image("AppLogo").resizable().scaledToFit().frame(width: 40, height: 40)
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
        .navigationDestination(item: $selectedHistoryRide) { ride in
            RideSummaryView(rideId: ride.rideId, rideTitle: ride.title, fallback: ride)
        }
        .task {
            if showNearbyRides {
                await loadNearby()
            } else {
                await loadRecent()
            }
        }
        .sheet(item: $selectedNearbyRide) { ride in
            RidePreviewSheet(ride: ride)
                .environmentObject(appState)
        }
    }

    // MARK: - Nearby content states

    @ViewBuilder
    private var nearbyContent: some View {
        switch nearbyState {
        case .loading:
            ProgressView()
                .tint(Color.primaryFixed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

        case .locationDenied:
            NearbyEmptyCard(
                icon: "location.slash.fill",
                title: "Location access needed",
                subtitle: "Enable location to discover rides starting near you.",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                actionLabel: "Open Settings"
            )

        case .error:
            NearbyEmptyCard(
                icon: "wifi.slash",
                title: "Couldn't load rides",
                subtitle: "Check your connection and try again.",
                action: { Task { await loadNearby() } },
                actionLabel: "Retry"
            )

        case .loaded:
            if displayedNearbyRides.isEmpty {
                NearbyEmptyCard(
                    icon: "road.lanes",
                    title: "No rides nearby",
                    subtitle: "No rides starting within 20 km. Be the first to plan one!",
                    action: { navPath.append(HomeRoute.createRide) },
                    actionLabel: "Create Ride"
                )
            } else {
                ForEach(displayedNearbyRides) { ride in
                    NearbyRideCard(ride: ride)
                        .onTapGesture { handleNearbyTap(ride) }
                }
            }
        }
    }

    // Hide the ride already surfaced in the Active Ride card to avoid duplication.
    private var displayedNearbyRides: [NearbyRide] {
        nearbyRides.filter { $0.id != appState.currentRideId }
    }

    private func handleNearbyTap(_ ride: NearbyRide) {
        // Never show the join sheet for a ride I already belong to. Check both the
        // server-provided viewerRole AND my leader id directly, so a leader is routed
        // to the lobby even if viewerRole is missing/stale (e.g. pre-deploy backend).
        let myId = clerk.user?.id
        let iAmLeader = myId != nil && ride.leaderId == myId
        if ride.isParticipant || iAmLeader {
            appState.inviteCode = ride.inviteCode
            appState.currentRideId = ride.id   // triggers onChange → pushes RideLobbyView
        } else {
            selectedNearbyRide = ride
        }
    }

    // MARK: - Load nearby

    private func loadNearby() async {
        nearbyState = .loading
        let authStatus = CLLocationManager().authorizationStatus
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            nearbyState = .locationDenied
            return
        }
        let loc: CLLocation? = await withCheckedContinuation { cont in
            LocationService.shared.requestCurrentLocation { cont.resume(returning: $0) }
        }
        guard let loc else { nearbyState = .error; return }
        do {
            nearbyRides = try await APIClient.shared.getNearbyRides(
                lat: loc.coordinate.latitude,
                lng:  loc.coordinate.longitude
            )
            nearbyState = .loaded
        } catch {
            nearbyState = .error
        }
    }

    // MARK: - Recent rides

    // Show the most recent rides; skip the one already surfaced in the Active Ride card.
    private var displayedRecentRides: [HistoryRide] {
        recentRides
            .filter { $0.rideId != appState.currentRideId }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var recentRidesSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RECENT RIDES").font(.headlineMd).foregroundColor(Color.onSurface)
                Spacer()
                if !displayedRecentRides.isEmpty {
                    Button(action: { activeTab = .flagged }) {
                        Text("SEE ALL")
                            .font(.labelCaps).tracking(1)
                            .foregroundColor(Color.primaryFixed)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    if recentLoading {
                        ProgressView()
                            .tint(Color.primaryFixed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if displayedRecentRides.isEmpty {
                        NearbyEmptyCard(
                            icon: "flag.checkered",
                            title: "No rides yet",
                            subtitle: "Your rides will show up here once you create or join your first convotrack.",
                            action: { navPath.append(HomeRoute.createRide) },
                            actionLabel: "Create Ride"
                        )
                    } else {
                        ForEach(displayedRecentRides) { ride in
                            RecentRideCard(ride: ride)
                                .onTapGesture { handleRecentTap(ride) }
                        }
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 20)
            }
            .refreshable { await loadRecent() }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func handleRecentTap(_ ride: HistoryRide) {
        if ride.status == "COMPLETED" {
            selectedHistoryRide = ride
        } else {
            if let code = ride.inviteCode { appState.inviteCode = code }
            appState.currentRideId = ride.rideId   // triggers onChange → pushes RideLobbyView
        }
    }

    private func loadRecent() async {
        recentRides = (try? await APIClient.shared.getMyRides()) ?? []
        recentLoading = false
    }
}

// MARK: - Recent Ride Card (compact home-screen row)

struct RecentRideCard: View {
    let ride: HistoryRide

    private var isCompleted: Bool { ride.status == "COMPLETED" }

    private var dateLabel: String {
        let iso = ride.endedAt ?? ride.startedAt ?? ride.createdAt
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f.string(from: date).uppercased()
    }

    private var distanceLabel: String {
        guard ride.distanceMeters > 0 else { return "--" }
        return String(format: "%.1f KM", ride.distanceMeters / 1000)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isCompleted ? Color.surfaceContainerHigh : Color.primaryFixed.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: isCompleted ? "flag.checkered" : "location.fill.viewfinder")
                    .font(.system(size: 22))
                    .foregroundColor(isCompleted ? Color.onSurfaceVariant : Color.primaryFixed)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(ride.title)
                        .font(.bodyLg).fontWeight(.bold)
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                    Spacer()
                    if !isCompleted {
                        Text("RESUME")
                            .font(.labelCaps).tracking(1)
                            .foregroundColor(Color.onPrimaryFixed)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.primaryFixed)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    if !dateLabel.isEmpty {
                        Text(dateLabel)
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant)
                        Text("·")
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
                    }
                    Image(systemName: "road.lanes")
                        .font(.system(size: 11))
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                    Text(distanceLabel)
                        .font(.dataMono)
                        .foregroundColor(Color.onSurfaceVariant)
                    if ride.isLeader == true {
                        Text("·")
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
                        Text("LEADER")
                            .font(.labelCaps)
                            .foregroundColor(Color.primaryFixed)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
        }
        .padding(14)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCompleted ? Color.outlineVariant.opacity(0.3) : Color.primaryFixed.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Nearby Ride Card

struct NearbyRideCard: View {
    let ride: NearbyRide

    var body: some View {
        HStack(spacing: 14) {
            // Icon column
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ride.isLive ? Color.primaryFixed.opacity(0.12) : Color.surfaceContainerHigh)
                    .frame(width: 52, height: 52)
                Image(systemName: ride.isLive ? "location.fill.viewfinder" : "road.lanes")
                    .font(.system(size: 22))
                    .foregroundColor(ride.isLive ? Color.primaryFixed : Color.onSurfaceVariant)
            }

            // Text column
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(ride.title)
                        .font(.bodyLg)
                        .fontWeight(.bold)
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                    Spacer()
                    if ride.isMine {
                        BadgeChip(text: "YOURS", fg: Color.onPrimaryFixed, bg: Color.primaryFixed)
                    } else if ride.isJoined {
                        BadgeChip(text: "JOINED", fg: Color.onPrimaryFixed, bg: Color.tertiaryFixed)
                    } else {
                        StatusBadge(isLive: ride.isLive)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.primaryFixed)
                    Text(ride.destinationName)
                        .font(.labelCaps)
                        .foregroundColor(Color.onSurfaceVariant)
                        .lineLimit(1)
                    Text("·")
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
                    Text(ride.formattedRideDistance)
                        .font(.labelCaps)
                        .foregroundColor(Color.onSurfaceVariant)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.6))
                    Text("\(ride.riderCount) rider\(ride.riderCount == 1 ? "" : "s")")
                        .font(.dataMono)
                        .foregroundColor(Color.onSurfaceVariant)
                    Text("·")
                        .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
                    Text(ride.formattedUserDistance)
                        .font(.dataMono)
                        .foregroundColor(Color.onSurfaceVariant)
                    if ride.isFull {
                        Text("· FULL")
                            .font(.labelCaps)
                            .foregroundColor(Color.errorColor.opacity(0.8))
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
        }
        .padding(14)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ride.isLive ? Color.primaryFixed.opacity(0.25) : Color.outlineVariant.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let isLive: Bool

    var body: some View {
        BadgeChip(
            text: isLive ? "LIVE" : "FORMING",
            fg: isLive ? Color.onPrimaryFixed : Color(red: 0.15, green: 0.10, blue: 0),
            bg: isLive ? Color.primaryFixed : Color(red: 1.0, green: 0.78, blue: 0.25)
        )
    }
}

private struct BadgeChip: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .font(.labelCaps)
            .tracking(1)
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }
}

// MARK: - Nearby Empty Card

private struct NearbyEmptyCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(Color.onSurfaceVariant.opacity(0.5))
            VStack(spacing: 6) {
                Text(title)
                    .font(.bodyLg).fontWeight(.semibold)
                    .foregroundColor(Color.onSurface)
                Text(subtitle)
                    .font(.bodyMd)
                    .foregroundColor(Color.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            Button(action: action) {
                Text(actionLabel)
                    .font(.labelCaps).tracking(1)
                    .foregroundColor(Color.onPrimaryFixed)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.primaryFixed)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Ride Preview Sheet

struct RidePreviewSheet: View {
    let ride: NearbyRide
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isJoining = false
    @State private var joinError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceDim.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Status + title block
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(isLive: ride.isLive)
                            Text(ride.title)
                                .font(.headlineLg)
                                .foregroundColor(Color.onSurface)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 28)

                        // Info rows
                        VStack(spacing: 0) {
                            infoRow(icon: "mappin.circle.fill",   label: "Destination",    value: ride.destinationName)
                            divider
                            infoRow(icon: "road.lanes",            label: "Ride distance",  value: ride.formattedRideDistance)
                            divider
                            infoRow(icon: "person.2.fill",         label: "Riders",         value: "\(ride.riderCount) / \(ride.maxParticipants)")
                            divider
                            infoRow(icon: "crown.fill",            label: "Led by",         value: ride.leaderName)
                            divider
                            infoRow(icon: "location.fill",         label: "Starts",         value: ride.formattedUserDistance)
                        }
                        .background(Color.surfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)

                        // Error
                        if let err = joinError {
                            Text(err)
                                .font(.bodyMd)
                                .foregroundColor(Color.errorColor)
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }

                        // Join CTA
                        VStack(spacing: 8) {
                            Button(action: { Task { await join() } }) {
                                Group {
                                    if isJoining {
                                        ProgressView().tint(Color.onPrimaryFixed)
                                    } else {
                                        Text(ride.isFull ? "RIDE IS FULL" : "JOIN RIDE")
                                            .font(.labelCaps).tracking(1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(ride.isFull ? Color.surfaceContainerHighest : Color.primaryFixed)
                                .foregroundColor(ride.isFull ? Color.onSurfaceVariant : Color.onPrimaryFixed)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isJoining || ride.isFull)

                            Text("You'll join as a Formation Rider")
                                .font(.labelCaps)
                                .foregroundColor(Color.onSurfaceVariant)
                                .tracking(1)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 36)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.onSurfaceVariant)
                            .frame(width: 30, height: 30)
                            .background(Color.surfaceContainerHigh)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.3))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(Color.primaryFixed)
                .frame(width: 22)
            Text(label)
                .font(.bodyMd)
                .foregroundColor(Color.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(.bodyMd).fontWeight(.medium)
                .foregroundColor(Color.onSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func join() async {
        joinError = nil
        isJoining = true
        do {
            try await APIClient.shared.joinRide(ride.id)
            appState.currentRideId = ride.id
            appState.inviteCode = ride.inviteCode
            dismiss()
        } catch APIClientError.serverError(let msg) {
            joinError = friendlyError(msg)
        } catch {
            joinError = "Something went wrong. Please try again."
        }
        isJoining = false
    }

    private func friendlyError(_ code: String) -> String {
        switch code {
        case "RIDE_FULL":       return "This ride is already full."
        case "QUOTA_EXCEEDED":  return "You've reached your monthly ride limit."
        case "ALREADY_JOINED":  return "You're already part of this ride."
        case "RIDE_NOT_ACTIVE": return "This ride is no longer accepting riders."
        default:                return "Couldn't join: \(code)"
        }
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
                Text("ACTIVE RIDE").font(.headlineMd).foregroundColor(Color.onSurface)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.primaryFixed).frame(width: 8, height: 8)
                    Text(statusLabel).font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                }
            }
            .padding(.horizontal, 20)

            Button(action: onTap) { ActiveRideCard(ride: ride) }
                .buttonStyle(PlainButtonStyle())
        }
        .task {
            guard ride == nil, let id = rideId else { return }
            guard let loaded = try? await APIClient.shared.getRide(id) else {
                onRideClear(); return
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
            if let ride, !ride.waypoints.isEmpty {
                let destPin = MapPin(
                    id: "dest",
                    coordinate: CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng),
                    style: .simpleDot(color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1), size: 10),
                    anchorBottom: false
                )
                GoogleMapView(routeCoords: routeCoordinates, pins: [destPin], cameraCommand: cameraCommand, isInteractive: false)
                    .task(id: ride.id) { await computeRoute(ride) }
            } else {
                LinearGradient(colors: [Color.surfaceContainerHigh, Color.surfaceDim], startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.55), Color.black.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 13)).foregroundColor(Color.primaryFixed)
                        Text(ride?.destinationName ?? "Loading…").font(.labelCaps).foregroundColor(.white).tracking(1).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial).clipShape(Capsule())
                    Spacer()
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ride?.title ?? "Loading…").font(.headlineMd).foregroundColor(.white)
                        HStack(spacing: 8) {
                            HStack(spacing: -6) {
                                ForEach(0..<max(1, min(participantCount, 3)), id: \.self) { _ in
                                    Circle().fill(Color.surfaceVariant).frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1.5))
                                }
                            }
                            Text("\(participantCount) Rider\(participantCount == 1 ? "" : "s") · \(rideStatus)")
                                .font(.dataMono).foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    Text("RESUME")
                        .font(.labelCaps).foregroundColor(Color.onPrimaryFixed).tracking(1)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.primaryFixed).clipShape(Capsule())
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
        // Prefer the leader-selected route geometry stored on the ride.
        if let stored = GoogleDirectionsService.decodedRoute(ride.routePolyline) {
            routeCoordinates = stored
            cameraCommand = MapCameraCommand.fitRoute(stored, padding: 48)
            return
        }
        let sorted = ride.waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }
        var allCoords: [CLLocationCoordinate2D] = []
        for i in 0..<sorted.count - 1 {
            let origin = CLLocationCoordinate2D(latitude: sorted[i].lat,   longitude: sorted[i].lng)
            let dest   = CLLocationCoordinate2D(latitude: sorted[i+1].lat, longitude: sorted[i+1].lng)
            if let result = try? await GoogleDirectionsService.route(from: origin, to: dest) {
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
            }
        }
        routeCoordinates = allCoords
        if !allCoords.isEmpty { cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 48) }
    }
}

#Preview {
    HomeView(activeTab: .constant(.track), showJoinRide: .constant(false))
        .environmentObject(AppState())
}
