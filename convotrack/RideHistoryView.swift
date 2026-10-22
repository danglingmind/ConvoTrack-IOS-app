import SwiftUI

struct RideHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @State private var rides: [HistoryRide] = []
    @State private var isLoading = true
    @State private var selectedRide: HistoryRide? = nil
    @State private var showSummary = false
    @State private var showLobby = false
    /// The inline "History" title only shows once the serif headline has scrolled away.
    @State private var titleVisible = false

    /// The server is asked for COMPLETED only; this stays as a guard so a future caller or a
    /// looser server response can't put an in-progress ride into the history list.
    private var completedRides: [HistoryRide] { rides.filter { $0.status == "COMPLETED" } }

    private var totalDistanceKm: Double {
        completedRides.reduce(0) { $0 + $1.distanceMeters / 1000 }
    }
    private var avgSpeedKmh: Double {
        let speeds = completedRides.compactMap { $0.avgSpeedKmh }
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    private var connectionState: DSConnectionState {
        switch rideSession.connectionState {
        case .connected: .connected
        case .reconnecting: .reconnecting
        case .disconnected: .offline
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                DSScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(topInset: proxy.safeAreaInsets.top)

                        VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                            if isLoading {
                                DSLoadingState()
                            } else {
                                statStrip
                                if completedRides.isEmpty {
                                    DSEmptyState(
                                        systemImage: "flag",
                                        title: "No rides yet",
                                        message: "Your ride history will appear here after you create or join your first ride."
                                    )
                                } else {
                                    rideList
                                }
                            }
                        }
                        .padding(.horizontal, DS.Space.screenInset)
                        .padding(.top, DS.Space.p4)
                        .padding(.bottom, DS.Space.sectionGap)
                    }
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: .top)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 70 } action: { _, scrolled in
                    titleVisible = scrolled
                }
                .refreshable { await loadHistory() }
            }
        }
        .navigationTitle(titleVisible ? String(localized: "History") : "")
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        // Hidden for now: the top-right slot is reserved for a notification bell.
        // .toolbar {
        //     // The connection indicator only means something while a ride session exists.
        //     if appState.currentRideId != nil {
        //         ToolbarItem(placement: .topBarTrailing) {
        //             DSConnectionStatusButton(state: connectionState)
        //         }
        //         .sharedBackgroundVisibility(.hidden)
        //     }
        // }
        .navigationDestination(isPresented: $showSummary) {
            if let ride = selectedRide {
                RideSummaryView(rideId: ride.rideId, rideTitle: ride.title, fallback: ride)
            }
        }
        .navigationDestination(isPresented: $showLobby) {
            RideLobbyView()
        }
        .onChange(of: appState.popToRoot) { _, shouldPop in
            if shouldPop { showLobby = false }
        }
        .task { await loadHistory() }
    }

    // MARK: - Sections

    /// Road photo (45%) fading into the base, with the serif headline in content.
    private func header(topInset: CGFloat) -> some View {
        DSHeroTitleBlock(title: "Ride history", compact: true)
            .padding(.horizontal, DS.Space.screenInset)
            .padding(.top, topInset + 8)
            .padding(.bottom, DS.Space.p4)
            .frame(maxWidth: .infinity, minHeight: topInset + 96, alignment: .bottomLeading)
            .background { DSHeroPhoto(imageName: "hero_road_sunset", height: nil, imageOpacity: 0.45) }
    }

    /// Three tiles that stack to one column at accessibility sizes.
    private var statStrip: some View {
        DSAdaptiveStack(spacing: 8, verticalAlignment: .top) {
            DSStatTile(
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                label: "Distance · last \(completedRides.count)",
                value: String(format: "%.0f km", totalDistanceKm),
                fillsWidth: true, showsIcon: false
            )
            DSStatTile(
                systemImage: "flag",
                label: "Rides shown",
                value: "\(completedRides.count)",
                fillsWidth: true, showsIcon: false
            )
            DSStatTile(
                systemImage: "speedometer",
                label: "Avg speed",
                value: avgSpeedKmh > 0 ? String(format: "%.0f km/h", avgSpeedKmh) : "--",
                fillsWidth: true, showsIcon: false
            )
        }
    }

    private var rideList: some View {
        VStack(spacing: 8) {
            ForEach(completedRides) { ride in
                Button { handleTap(ride) } label: { RideRow(ride: ride) }
                    .buttonStyle(.plain)
            }
        }
        // Rows break out to a 12 pt inset, as on Home, so name and facts fit on a 402 pt screen.
        .padding(.horizontal, -(DS.Space.screenInset - DS.Space.p3))
    }

    private func handleTap(_ ride: HistoryRide) {
        selectedRide = ride
        if ride.status == "COMPLETED" {
            showSummary = true
        } else {
            appState.currentRideId = ride.rideId
            if let code = ride.inviteCode { appState.inviteCode = code }
            showLobby = true
        }
    }

    private func loadHistory() async {
        rides = (try? await APIClient.shared.getMyRides(
            statuses: APIClient.RideStatusFilter.completed
        )) ?? []
        isLoading = false
    }
}

#Preview {
    RideHistoryView()
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
}
