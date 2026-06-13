import SwiftUI
import ClerkKit

enum HomeRoute: Hashable {
    case createRide
    case rideLobby
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(Clerk.self) private var clerk
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
                        // Greeting
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("STATUS: READY TO RIDE")
                                    .font(.labelCaps)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .tracking(4)
                                Text("Hey, \(clerkDisplayName)")
                                    .font(.headlineLg)
                                    .foregroundColor(Color.onSurface)
                            }
                            Spacer()
                            ZStack(alignment: .bottomTrailing) {
                                AsyncImage(url: clerkImageUrl) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                                    default:
                                        Circle()
                                            .fill(Color.surfaceVariant)
                                            .frame(width: 56, height: 56)
                                            .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                                            .overlay(
                                                Text(String(clerkDisplayName.prefix(1)).uppercased())
                                                    .font(.headlineMd).foregroundColor(Color.primaryFixed)
                                            )
                                    }
                                }
                                Circle()
                                    .fill(Color.primaryFixed)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: Color.primaryFixed, radius: 4)
                            }
                        }
                        .padding(.horizontal, 20)

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
                                        Button(action: {
                                            selectedRide = ride
                                            showRideSummary = true
                                        }) {
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
            .ignoresSafeArea(edges: .bottom)

            ConvoyTopBar(title: "APEX CONVOY")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Helpers

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

    private var clerkDisplayName: String {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? (clerk.user?.username ?? "Rider") : name
    }

    private var clerkImageUrl: URL? {
        guard let str = clerk.user?.imageUrl, !str.isEmpty else { return nil }
        return URL(string: str)
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

    private var participantCount: Int { ride?.participants.count ?? 0 }
    private var rideStatus: String {
        guard let s = ride?.status else { return "LOBBY" }
        return s == "IN_PROGRESS" ? "RIDING" : s
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color.primaryFixed.opacity(0.1), Color.surfaceContainerLow],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, minHeight: 100)

                VStack(alignment: .leading, spacing: 4) {
                    Text("DESTINATION")
                        .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                    Text(ride?.destinationName ?? "Loading…")
                        .font(.bodyLg).foregroundColor(Color.onSurface).fontWeight(.bold)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ride?.title ?? "Loading…")
                        .font(.headlineMd).foregroundColor(Color.onSurface)
                    HStack(spacing: 8) {
                        HStack(spacing: -6) {
                            ForEach(0..<max(1, min(participantCount, 3)), id: \.self) { _ in
                                Circle().fill(Color.surfaceVariant).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.surfaceContainerHigh, lineWidth: 2))
                            }
                        }
                        Text("\(participantCount) Rider\(participantCount == 1 ? "" : "s") • \(rideStatus)")
                            .font(.dataMono).foregroundColor(Color.onSurfaceVariant)
                    }
                }
                Spacer()
                Text("RESUME RIDE")
                    .font(.labelCaps)
                    .foregroundColor(Color.onPrimaryContainer)
                    .tracking(1)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.primaryContainer)
                    .clipShape(Capsule())
                    .shadow(color: Color.primaryFixed.opacity(0.3), radius: 12)
            }
            .padding(16)
        }
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primaryFixed.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 20)
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
