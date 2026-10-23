import SwiftUI
import CoreLocation

// MARK: - Create Ride View

struct CreateRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @Environment(\.dismiss) private var dismiss

    @State private var rideTitle = ""
    @State private var maxRiders = 5
    @EnvironmentObject private var paywall: PaywallPresenter

    private var riderCap: Int { membershipStore.riderCap }

    // Route stops — start + optional middle waypoints + destination
    @State private var startStop = RouteStop()
    @State private var middleStops: [RouteStop] = []
    @State private var endStop = RouteStop()

    // Computed route
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeDistance: Double = 0
    @State private var routeDuration: TimeInterval = 0
    @State private var cameraCommand: MapCameraCommand? = nil

    // Alternative routes — only populated for a direct start→destination (no middle stops)
    @State private var routeAlternatives: [RouteOption] = []
    @State private var selectedRouteIndex = 0

    // API state
    @State private var isCreating = false
    @State private var errorMessage: String?
    /// The last create was refused for a plan reason (trial over / monthly rides used up).
    @State private var createBlockedByPlan = false
    @State private var showError = false

    @State private var scrollTarget: String? = nil

    private var canCreate: Bool {
        !rideTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && startStop.place != nil
            && endStop.place != nil
            && !isCreating
    }

    // All confirmed stops in order for route calc and annotations
    private var confirmedStops: [PlaceResult] {
        var stops: [PlaceResult] = []
        if let s = startStop.place { stops.append(s) }
        stops += middleStops.compactMap { $0.place }
        if let e = endStop.place { stops.append(e) }
        return stops
    }

    private var connectionState: DSConnectionState {
        switch rideSession.connectionState {
        case .connected: .connected
        case .reconnecting: .reconnecting
        case .disconnected: .offline
        }
    }

    var body: some View {
        // Background is a `.background`, not a full-bleed child: as a child its safe-area handling
        // starves keyboard avoidance and the focused field can sit under the keyboard.
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    RideRouteForm(
                        title: $rideTitle,
                        startStop: $startStop,
                        middleStops: $middleStops,
                        endStop: $endStop,
                        maxRiders: $maxRiders,
                        scrollTarget: $scrollTarget,
                        riderCap: riderCap,
                        isPremium: membershipStore.isPremium,
                        routeCoordinates: routeCoordinates,
                        routeAlternatives: routeAlternatives,
                        selectedRouteIndex: selectedRouteIndex,
                        cameraCommand: cameraCommand,
                        confirmedStops: confirmedStops,
                        distanceMeters: routeDistance,
                        durationSeconds: routeDuration,
                        onStopsChanged: { Task { await recalculateRoute() } },
                        onSelectRoute: { selectRoute($0) },
                        onUpgrade: { paywall.present(.riderCap) }
                    )
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.top, proxy.safeAreaInsets.top + DS.Space.p4)
                    .padding(.bottom, DS.Space.p6)
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            scroll.scrollTo(target, anchor: .bottom)
                        }
                        scrollTarget = nil
                    }
                }
                .ignoresSafeArea(edges: .top)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                DSScreenBackground()
                DSHeroPhoto(imageName: "hero_road_sunset", height: 150 + 100, imageOpacity: 0.45)
                    .ignoresSafeArea(edges: .top)
            }
            .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        // Sticky action above the home indicator, with the fade.
        .dsStickyBottomAction {
            DSPrimaryButton(title: "Create ride", systemImage: "arrow.turn.up.right", isLoading: isCreating) {
                Task { await createRide() }
            }
            .disabled(!canCreate)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("New Ride")
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        // Hidden for now: the top-right slot is reserved for a notification bell.
        // .toolbar {
        //     if appState.currentRideId != nil {
        //         ToolbarItem(placement: .topBarTrailing) {
        //             DSConnectionStatusButton(state: connectionState)
        //         }
        //         .sharedBackgroundVisibility(.hidden)
        //     }
        // }
        .alert("Failed to Create Ride", isPresented: $showError) {
            if createBlockedByPlan {
                Button("Go Pro") { paywall.present(.createBlocked) }
                Button("Not now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .onAppear {
            // Clamp to plan limit in case default exceeds it (e.g. free tier = 5)
            // First ride only: start from the group size the rider told us during onboarding.
            if let suggested = OnboardingState.consumeSuggestedMaxRiders() {
                maxRiders = max(2, suggested)
            }
            maxRiders = min(maxRiders, riderCap)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Route Calculation

    @MainActor
    private func recalculateRoute() async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeAlternatives  = []
            selectedRouteIndex = 0
            routeCoordinates   = []
            routeDistance      = 0
            routeDuration      = 0
            if let first = stops.first {
                cameraCommand = MapCameraCommand.focus(lat: first.coordinate.latitude, lng: first.coordinate.longitude, zoom: 13)
            }
            return
        }

        // Direct start→destination: offer selectable alternatives.
        // (Google returns none once intermediate waypoints are present.)
        if stops.count == 2 {
            do {
                let options = try await GoogleDirectionsService.alternativeRoutes(from: stops[0].coordinate, to: stops[1].coordinate)
                if options.count > 1 {
                    routeAlternatives = options
                    selectRoute(0, fitCamera: true)
                    return
                }
            } catch { /* fall through to the single-route path below */ }
        }

        // Has middle stops, or only one/zero alternatives: single stitched route.
        routeAlternatives  = []
        selectedRouteIndex = 0

        var allCoords: [CLLocationCoordinate2D] = []
        var totalDist: Double = 0
        var totalTime: TimeInterval = 0

        for i in 0..<stops.count - 1 {
            do {
                let result = try await GoogleDirectionsService.route(from: stops[i].coordinate, to: stops[i+1].coordinate)
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
                totalDist += result.distanceMeters
                totalTime += result.durationSeconds
            } catch { continue }
        }

        routeCoordinates = allCoords
        routeDistance    = totalDist
        routeDuration    = totalTime

        if !allCoords.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 40)
        }
    }

    /// Applies the alternative at `index` as the active route. `fitCamera` is true only
    /// for the initial pick; manual selection keeps the camera steady (endpoints match).
    @MainActor
    private func selectRoute(_ index: Int, fitCamera: Bool = false) {
        guard routeAlternatives.indices.contains(index) else { return }
        selectedRouteIndex = index
        let option = routeAlternatives[index]
        routeCoordinates = option.coordinates
        routeDistance    = option.distanceMeters
        routeDuration    = option.durationSeconds
        if fitCamera, !option.coordinates.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(option.coordinates, padding: 40)
        }
    }

    // MARK: - Create Ride

    @MainActor
    private func createRide() async {
        guard let start = startStop.place, let dest = endStop.place else { return }
        isCreating = true
        defer { isCreating = false }

        let destCoord       = dest.coordinate
        let encodedPolyline = GoogleDirectionsService.encodePolyline(routeCoordinates)

        // Build ordered waypoints: START → WAYPOINT* → DESTINATION
        var waypoints: [CreateWaypoint] = []
        let startCoord = start.coordinate
        waypoints.append(CreateWaypoint(
            order: 0,
            name: start.name,
            type: "START",
            lat: startCoord.latitude,
            lng: startCoord.longitude
        ))
        for stop in middleStops {
            guard let place = stop.place else { continue }
            let c = place.coordinate
            waypoints.append(CreateWaypoint(
                order: waypoints.count,
                name: place.name,
                type: "WAYPOINT",
                lat: c.latitude,
                lng: c.longitude
            ))
        }
        waypoints.append(CreateWaypoint(
            order: waypoints.count,
            name: dest.name,
            type: "DESTINATION",
            lat: destCoord.latitude,
            lng: destCoord.longitude
        ))

        let body = CreateRideRequest(
            title: rideTitle.trimmingCharacters(in: .whitespaces),
            destinationName: dest.name,
            destinationLat: destCoord.latitude,
            destinationLng: destCoord.longitude,
            distanceMeters: routeDistance,
            estimatedDurationSeconds: Int(routeDuration),
            maxAllowedParticipants: maxRiders,
            routePolyline: encodedPolyline,
            waypoints: waypoints
        )

        do {
            let response = try await APIClient.shared.createRide(body)
            // Seed the full ride BEFORE flipping `currentRideId` — that assignment is what
            // pushes the lobby, and the lobby, the home Active Ride card and the navigation
            // screen all read `currentRide` on their first frame. Leaving it nil there is what
            // left the hero photo blank (`destinationPhotoKey` stays empty, so the hero parks in
            // `.resolving` forever), demoted the leader to a MARK AS READY button, and sent
            // `ActiveRideSection` off on a duplicate concurrent fetch of its own.
            //
            // A failed fetch assigns nil, which is exactly the old behaviour — no stale ride can
            // survive here — and the lobby's own retrying fetch then fills it in.
            appState.currentRide = try? await APIClient.shared.getRide(response.rideId)
            appState.inviteCode = response.inviteCode
            appState.currentRideId = response.rideId
        } catch {
            Analytics.capture(.createRideFailed, ["plan_limit": error.isPlanLimit])
            errorMessage = error.riderMessage
            createBlockedByPlan = error.isPlanLimit
            showError = true
        }
    }
}

#Preview {
    CreateRideView()
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
}
