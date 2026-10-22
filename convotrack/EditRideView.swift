import SwiftUI
import CoreLocation
import ClerkKit

struct EditRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss

    let ride: Ride

    /// Called after the ride is successfully deleted, so the presenting lobby can tear
    /// down its session and pop back instead of refreshing a now-nonexistent ride.
    var onDeleted: () -> Void = {}

    @State private var rideTitle: String
    @State private var maxRiders: Int

    private var riderCap: Int { membershipStore.riderCap }

    @State private var startStop: RouteStop
    @State private var middleStops: [RouteStop]
    @State private var endStop: RouteStop

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeDistance: Double = 0
    @State private var routeDuration: TimeInterval = 0
    @State private var cameraCommand: MapCameraCommand? = nil

    // Alternative routes — only populated for a direct start→destination (no middle stops)
    @State private var routeAlternatives: [RouteOption] = []
    @State private var selectedRouteIndex = 0

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @EnvironmentObject private var paywall: PaywallPresenter

    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    /// Only the ride's creator (leader) may delete it. Read reactively from Clerk so a
    /// still-loading identity resolves the moment it lands.
    private var isLeader: Bool {
        guard let uid = clerk.user?.id, !uid.isEmpty else { return false }
        return uid == ride.leaderId
    }

    @State private var scrollTarget: String? = nil

    init(ride: Ride, onDeleted: @escaping () -> Void = {}) {
        self.ride = ride
        self.onDeleted = onDeleted
        _rideTitle = State(initialValue: ride.title)
        _maxRiders = State(initialValue: ride.maxAllowedParticipants)

        let sorted = ride.waypoints.sorted { $0.order < $1.order }

        if let wp = sorted.first(where: { $0.type == "START" }) {
            let place = PlaceResult(id: "wp_start", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            _startStop = State(initialValue: RouteStop(text: wp.name, place: place))
        } else {
            _startStop = State(initialValue: RouteStop())
        }

        let midWaypoints = sorted.filter { $0.type == "WAYPOINT" }
        _middleStops = State(initialValue: midWaypoints.map { wp in
            let place = PlaceResult(id: "wp_\(wp.order)", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            return RouteStop(text: wp.name, place: place)
        })

        if let wp = sorted.first(where: { $0.type == "DESTINATION" }) {
            let place = PlaceResult(id: "wp_dest", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            _endStop = State(initialValue: RouteStop(text: wp.name, place: place))
        } else {
            _endStop = State(initialValue: RouteStop())
        }
    }

    private var canSave: Bool {
        !rideTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && startStop.place != nil
            && endStop.place != nil
            && routeDistance > 0
            && !isSaving
    }

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
        // Background is a `.background`, not a full-bleed child inside the stack. As a child, its
        // `.ignoresSafeArea()` consumed the safe area for the ScrollView, and the keyboard is
        // reported through the safe area, so keyboard avoidance had nothing to shrink and the
        // focused field could sit under the keyboard. This form has five text fields (title plus
        // every stop), so it was the worst affected screen.
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
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
                        deleteRideButton
                    }
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
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
        }
        // Sticky action above the home indicator, with the fade.
        .dsStickyBottomAction {
            DSPrimaryButton(title: "Save ride", systemImage: "arrow.turn.up.right", isLoading: isSaving) {
                Task { await saveRide() }
            }
            .disabled(!canSave)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Edit Ride")
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        // Hidden for now: the top-right slot is reserved for a notification bell.
        // .toolbar {
        //     // Editing happens inside a ride session, so the connection indicator applies.
        //     ToolbarItem(placement: .topBarTrailing) {
        //         DSConnectionStatusButton(state: connectionState)
        //     }
        //     .sharedBackgroundVisibility(.hidden)
        // }
        .alert("Failed to Save Ride", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Delete This Ride?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Ride", role: .destructive) { Task { await deleteRide() } }
        } message: {
            Text("This permanently deletes the ride for everyone. This can't be undone.")
        }
        .alert("Failed to Delete Ride", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "An unknown error occurred.")
        }
        .task {
            // Show the currently-saved route instantly, then load alternatives and
            // preselect the one matching it.
            if let stored = GoogleDirectionsService.decodedRoute(ride.routePolyline) {
                routeCoordinates = stored
                routeDistance    = ride.distanceMeters
                routeDuration    = TimeInterval(ride.estimatedDurationSeconds)
                cameraCommand    = MapCameraCommand.fitRoute(stored, padding: 40)
            }
            await recalculateRoute(preferStoredMatch: true)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Route Calculation

    @MainActor
    private func recalculateRoute(preferStoredMatch: Bool = false) async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeAlternatives  = []
            selectedRouteIndex = 0
            routeCoordinates = []
            routeDistance    = 0
            routeDuration    = 0
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
                    // On initial load, keep the leader's saved route selected.
                    selectRoute(preferStoredMatch ? bestMatchIndex(options) : 0, fitCamera: true)
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

    /// Picks the alternative closest to the ride's saved distance, so re-opening edit
    /// keeps the leader's previously-selected route highlighted.
    private func bestMatchIndex(_ options: [RouteOption]) -> Int {
        let target = ride.distanceMeters
        guard target > 0 else { return 0 }
        var best = 0
        var bestDiff = Double.greatestFiniteMagnitude
        for (i, option) in options.enumerated() {
            let diff = abs(option.distanceMeters - target)
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return best
    }

    // MARK: - Delete

    // Destructive action at the end of the form, shown only to the ride's creator (leader);
    // disabled while a save or delete is already in flight. Never the primary role.
    @ViewBuilder
    private var deleteRideButton: some View {
        if isLeader {
            DSDestructiveButton(title: "Delete ride", systemImage: "trash", isLoading: isDeleting) {
                showDeleteConfirm = true
            }
            .disabled(isDeleting || isSaving)
        }
    }

    @MainActor
    private func deleteRide() async {
        guard isLeader else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteRide(ride.id)
            await ImageCache.shared.purge(tag: ride.id)   // its map snapshot and share card
            RideThumbnail.forgetDestination(rideId: ride.id)
            onDeleted()
            dismiss()
        } catch {
            deleteErrorMessage = error.riderMessage
            showDeleteError = true
        }
    }

    // MARK: - Save

    @MainActor
    private func saveRide() async {
        guard let start = startStop.place, let dest = endStop.place else { return }
        isSaving = true
        defer { isSaving = false }

        let destCoord       = dest.coordinate
        let encodedPolyline = GoogleDirectionsService.encodePolyline(routeCoordinates)

        var waypoints: [CreateWaypoint] = []
        let startCoord = start.coordinate
        waypoints.append(CreateWaypoint(order: 0, name: start.name, type: "START",
                                        lat: startCoord.latitude, lng: startCoord.longitude))
        for stop in middleStops {
            guard let place = stop.place else { continue }
            let c = place.coordinate
            waypoints.append(CreateWaypoint(order: waypoints.count, name: place.name, type: "WAYPOINT",
                                            lat: c.latitude, lng: c.longitude))
        }
        waypoints.append(CreateWaypoint(order: waypoints.count, name: dest.name, type: "DESTINATION",
                                        lat: destCoord.latitude, lng: destCoord.longitude))

        let request = UpdateRideRequest(
            title:                    rideTitle.trimmingCharacters(in: .whitespaces),
            destinationName:          dest.name,
            destinationLat:           destCoord.latitude,
            destinationLng:           destCoord.longitude,
            distanceMeters:           routeDistance,
            estimatedDurationSeconds: Int(routeDuration),
            maxAllowedParticipants:   maxRiders,
            routePolyline:            encodedPolyline,
            waypoints:                waypoints
        )

        do {
            try await APIClient.shared.updateRide(ride.id, request)
            // New route/destination: drop the ride's cached map and card, and the remembered
            // destination so history thumbnails re-resolve the photo for the new place.
            await ImageCache.shared.purge(tag: ride.id)
            RideThumbnail.forgetDestination(rideId: ride.id)
            dismiss()
        } catch {
            errorMessage = error.riderMessage
            showError = true
        }
    }
}
