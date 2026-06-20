import SwiftUI
import MapKit
import ClerkKit
import Combine

// MARK: - Display Models

struct LiveRider: Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let rank: Int
    let distanceToGoalKm: Double
    let speedKmh: Double
    let coordinate: CLLocationCoordinate2D
    let isMe: Bool
}

struct NavLeaderboardRow: Identifiable {
    let id: String
    let rank: Int
    let name: String
    let avatarUrl: String?
    let distanceToGoalKm: Double
    let isMe: Bool
}

// MARK: - NavigationViewModel

@MainActor
final class NavigationViewModel: ObservableObject, LocationServiceDelegate {
    @Published var riders: [LiveRider] = []
    @Published var leaderboardRows: [NavLeaderboardRow] = []
    @Published var mySpeedKmh: Double = 0
    @Published var myRank: Int = 0
    @Published var myDistanceToGoalKm: Double = 0
    @Published var riderCount: Int = 0
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var routeVersion: Int = 0   // increments when route is ready; Equatable
    @Published var destinationCoordinate: CLLocationCoordinate2D? = nil
    @Published var startCoordinate: CLLocationCoordinate2D? = nil
    @Published var middleWaypoints: [Waypoint] = []
    @Published var locationTick: Int = 0   // increments each update, triggers camera onChange
    @Published var userHeading: Double = 0
    private(set) var userLocation: CLLocationCoordinate2D? = nil
    @Published var showSplitAlert = false
    @Published var showSummary = false
    @Published var isEnding = false
    @Published var endError: String? = nil
    @Published var currentInstruction: String = ""
    @Published var distanceToNextTurnMeters: Double = 0
    @Published var rerouteCoordinates: [CLLocationCoordinate2D] = []
    @Published var isOffRoute: Bool = false
    @Published var activeRegroup: RegroupEvent? = nil
    @Published var hasMarkedArrived: Bool = false
    @Published var showRegroupToast: Bool = false
    @Published var showRegroupResolvedToast: Bool = false

    var amILeader: Bool { !myUserId.isEmpty && myUserId == leaderId }

    var etaString: String {
        guard routeExpectedTravelTime > 0, totalDistanceMeters > 0, myDistanceToGoalKm >= 0 else { return "--:--" }
        let remainingFraction = (myDistanceToGoalKm * 1000) / totalDistanceMeters
        let remainingSecs = routeExpectedTravelTime * max(0, remainingFraction)
        let arrival = Date().addingTimeInterval(remainingSecs)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: arrival)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private struct NavStep {
        let instruction: String
        let endCoordinate: CLLocationCoordinate2D
        let distanceMeters: Double
    }

    private var rideId = ""
    private var staticParticipants: [RideParticipant] = []
    private var myUserId = ""
    private var leaderId = ""
    private var totalDistanceMeters: Double = 0
    private var routeExpectedTravelTime: TimeInterval = 0
    private var navSteps: [NavStep] = []
    private var currentStepIndex: Int = 0
    private var lastBroadcastDate: Date = .distantPast
    private var lastCameraTickDate: Date = .distantPast
    private var remainingStops: [CLLocationCoordinate2D] = []
    private var rerouteTask: Task<Void, Never>? = nil
    private var regroupResolvedToastTask: Task<Void, Never>? = nil
    private var isRerouteInFlight = false
    private var lastRerouteOrigin: CLLocation? = nil
    private let offRouteThresholdMeters: Double = 40
    private var currentRouteSegmentIndex: Int = 0
    private var consecutiveOffCount: Int = 0
    private var consecutiveOnCount: Int = 0
    private let offRouteConfirmCount = 3   // consecutive off-route readings before flagging
    private let onRouteClearCount = 4      // consecutive on-route readings before clearing

    func setup(rideId: String, ride: Ride, myUserId: String) async {
        self.rideId = rideId
        self.staticParticipants = ride.participants
        self.myUserId = myUserId
        self.leaderId = ride.leaderId
        self.totalDistanceMeters = ride.distanceMeters

        let sorted = ride.waypoints.sorted { $0.order < $1.order }
        if let dest = sorted.last {
            destinationCoordinate = CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lng)
        }
        if let start = sorted.first {
            startCoordinate = CLLocationCoordinate2D(latitude: start.lat, longitude: start.lng)
        }
        middleWaypoints = sorted.filter { $0.type == "WAYPOINT" }
        remainingStops = sorted
            .filter { $0.type == "WAYPOINT" || $0.type == "DESTINATION" }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }

        // Pre-populate leaderboard so it shows immediately before any socket updates
        let active = ride.participants.filter { $0.status != "LEFT" }
        leaderboardRows = active.enumerated().map { index, p in
            NavLeaderboardRow(
                id: p.userId, rank: index + 1, name: p.name,
                avatarUrl: p.avatarUrl,
                distanceToGoalKm: ride.distanceMeters / 1000,
                isMe: p.userId == myUserId
            )
        }
        riderCount = active.count
        if let myRow = leaderboardRows.first(where: { $0.isMe }) {
            myRank = myRow.rank
            myDistanceToGoalKm = ride.distanceMeters / 1000
        }

        await calculateRoute(from: ride.waypoints)

        let socket = SocketClient.shared
        socket.onStateUpdate = { [weak self] update in self?.handleStateUpdate(update) }
        socket.onSplitDetected = { [weak self] _ in self?.showSplitAlert = true }
        socket.onSplitResolved = { [weak self] in self?.showSplitAlert = false }
        socket.onRegroupStarted = { [weak self] event in self?.handleRegroupStarted(event) }
        socket.onRegroupResolved = { [weak self] regroupId in self?.handleRegroupResolved(regroupId) }

        // Re-join room so the server sends the current state snapshot to this client
        // and so state updates are received after any socket reconnect.
        socket.joinRoom(rideId: rideId)

        LocationService.shared.delegate = self
        LocationService.shared.onHeadingUpdate = { [weak self] heading in
            guard let self else { return }
            let raw = abs(heading - self.userHeading).truncatingRemainder(dividingBy: 360)
            let delta = min(raw, 360 - raw)
            guard delta >= 5 else { return }
            self.userHeading = heading
        }
        LocationService.shared.requestPermission()
        LocationService.shared.start()
    }

    func teardown() {
        rerouteTask?.cancel()
        regroupResolvedToastTask?.cancel()
        LocationService.shared.stop()
        LocationService.shared.delegate = nil
        LocationService.shared.onHeadingUpdate = nil
        SocketClient.shared.onStateUpdate = nil
        SocketClient.shared.onSplitDetected = nil
        SocketClient.shared.onSplitResolved = nil
        SocketClient.shared.onRegroupStarted = nil
        SocketClient.shared.onRegroupResolved = nil
        SocketClient.shared.onParticipantOffline = nil
    }

    func endRide() async {
        isEnding = true
        endError = nil
        do {
            try await APIClient.shared.endRide(rideId)
            showSummary = true
        } catch {
            endError = error.localizedDescription
        }
        isEnding = false
    }

    func broadcastRegroup(reason: CoordinationOverlayView.RegroupReason?, at coordinate: CLLocationCoordinate2D? = nil) {
        guard let reason else { return }
        let lat: Double
        let lng: Double
        if let coordinate {
            lat = coordinate.latitude
            lng = coordinate.longitude
        } else if let last = LocationService.shared.lastLocation {
            lat = last.coordinate.latitude
            lng = last.coordinate.longitude
        } else {
            return
        }
        if reason.isEmergency {
            SocketClient.shared.emitEmergency(rideId: rideId, lat: lat, lng: lng, message: "Emergency")
        } else {
            let type: String
            switch reason {
            case .fuel:      type = "FUEL"
            case .food:      type = "FOOD"
            case .scenic:    type = "SCENIC"
            case .emergency: return
            }
            SocketClient.shared.emitRegroup(rideId: rideId, type: type, lat: lat, lng: lng) { _ in }
        }
    }

    func markArrivedAtRegroup() {
        guard let regroup = activeRegroup else { return }
        SocketClient.shared.emitRegroupArrived(rideId: rideId, regroupId: regroup.regroupId)
        hasMarkedArrived = true
    }

    private func handleRegroupStarted(_ event: RegroupEvent) {
        activeRegroup = event
        hasMarkedArrived = false
        // Only toast for riders who didn't broadcast it
        if event.createdBy != myUserId {
            showRegroupToast = true
        }
    }

    private func handleRegroupResolved(_ regroupId: String) {
        guard activeRegroup?.regroupId == regroupId else { return }
        activeRegroup = nil
        hasMarkedArrived = false
        showRegroupToast = false
        showRegroupResolvedToast = true
        regroupResolvedToastTask?.cancel()
        regroupResolvedToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.showRegroupResolvedToast = false
        }
    }

    // MARK: - LocationServiceDelegate

    func locationService(_ service: LocationService, didUpdate location: CLLocation, battery: Double, signalStrength: String) {
        mySpeedKmh = max(0, location.speed * 3.6)
        userLocation = location.coordinate
        if location.course >= 0 { userHeading = location.course }
        updateCurrentStep(location: location)
        checkOffRoute(location: location)

        let now = Date()
        // Cap camera updates at ~10 Hz so overlapping animations don't jam the map
        if now.timeIntervalSince(lastCameraTickDate) >= 0.1 {
            lastCameraTickDate = now
            locationTick += 1
        }

        guard now.timeIntervalSince(lastBroadcastDate) >= 2.0 else { return }
        lastBroadcastDate = now
        SocketClient.shared.emitLocationUpdate(
            rideId: rideId,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: location.speed,
            heading: location.course,
            battery: battery,
            signalStrength: signalStrength
        )
    }

    // MARK: - Private

    private func handleStateUpdate(_ update: RideStateUpdate) {
        riderCount = update.participants.count

        // Only overwrite the pre-populated leaderboard when the server actually has data.
        // The initial ride:state_update emitted on start has leaderboard: [] before any
        // location updates have been processed — don't let that clear what we pre-seeded.
        if !update.leaderboard.isEmpty {
            leaderboardRows = update.leaderboard.map { entry in
                let participant = staticParticipants.first { $0.userId == entry.userId }
                let distKm = max(0, (totalDistanceMeters - entry.progress) / 1000)
                return NavLeaderboardRow(
                    id: entry.userId, rank: entry.rank, name: entry.name,
                    avatarUrl: participant?.avatarUrl,
                    distanceToGoalKm: distKm,
                    isMe: entry.userId == myUserId
                )
            }
        }

        riders = update.participants.compactMap { live in
            guard let lat = live.lat, let lng = live.lng else { return nil }
            let participant = staticParticipants.first { $0.userId == live.userId }
            let lbEntry = update.leaderboard.first { $0.userId == live.userId }
            let distKm = max(0, (totalDistanceMeters - live.progress) / 1000)
            return LiveRider(
                id: live.userId,
                name: participant?.name ?? lbEntry?.name ?? "Rider",
                avatarUrl: participant?.avatarUrl,
                rank: lbEntry?.rank ?? 99,
                distanceToGoalKm: distKm,
                speedKmh: (live.speed ?? 0) * 3.6,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                isMe: live.userId == myUserId
            )
        }

        if let myEntry = update.leaderboard.first(where: { $0.userId == myUserId }) {
            myRank = myEntry.rank
            myDistanceToGoalKm = max(0, (totalDistanceMeters - myEntry.progress) / 1000)
        }

        if update.status == "COMPLETED" { showSummary = true }

        // Late-join: pick up any open regroup from state snapshot
        if activeRegroup == nil, let incoming = update.openRegroup {
            handleRegroupStarted(incoming)
        }
    }

    private func calculateRoute(from waypoints: [Waypoint]) async {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }
        let items = sorted.map {
            MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)))
        }
        var allCoords: [CLLocationCoordinate2D] = []
        var totalTime: TimeInterval = 0
        var steps: [NavStep] = []
        for i in 0..<items.count - 1 {
            let req = MKDirections.Request()
            req.source = items[i]; req.destination = items[i + 1]; req.transportType = .automobile
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                let coords = route.polyline.coordinates
                allCoords += (i == 0) ? coords : Array(coords.dropFirst())
                totalTime += route.expectedTravelTime
                for step in route.steps {
                    let instr = step.instructions.trimmingCharacters(in: .whitespaces)
                    guard !instr.isEmpty, let end = step.polyline.coordinates.last else { continue }
                    steps.append(NavStep(instruction: instr, endCoordinate: end, distanceMeters: step.distance))
                }
            }
        }
        navSteps = steps
        currentStepIndex = 0
        if let first = navSteps.first {
            currentInstruction = first.instruction
            distanceToNextTurnMeters = first.distanceMeters
        }
        routeCoordinates = allCoords
        routeExpectedTravelTime = totalTime
        currentRouteSegmentIndex = 0
        consecutiveOffCount = 0
        consecutiveOnCount = 0
        routeVersion += 1
    }

    private func updateCurrentStep(location: CLLocation) {
        guard currentStepIndex < navSteps.count else { return }
        let step = navSteps[currentStepIndex]
        let endLoc = CLLocation(latitude: step.endCoordinate.latitude, longitude: step.endCoordinate.longitude)
        distanceToNextTurnMeters = location.distance(from: endLoc)
        if distanceToNextTurnMeters < 30, currentStepIndex + 1 < navSteps.count {
            currentStepIndex += 1
            currentInstruction = navSteps[currentStepIndex].instruction
        }
    }

    private func checkOffRoute(location: CLLocation) {
        while let next = remainingStops.first {
            let dist = location.distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
            guard dist < 80 else { break }
            remainingStops.removeFirst()
        }

        advanceRouteProgress(to: location)
        let rawOffRoute = minimumDistanceToUpcomingRoute(from: location) > offRouteThresholdMeters

        if rawOffRoute {
            consecutiveOffCount += 1
            consecutiveOnCount = 0
        } else {
            consecutiveOnCount += 1
            consecutiveOffCount = 0
        }

        if !isOffRoute && consecutiveOffCount >= offRouteConfirmCount {
            isOffRoute = true
        } else if isOffRoute && consecutiveOnCount >= onRouteClearCount {
            isOffRoute = false
        }

        if isOffRoute {
            // Never cancel an in-flight MKDirections request — that was the root bug.
            // Only start a new request when none is running, and refresh every 150 m of
            // travel so the road-following polyline stays current as the user moves.
            guard !isRerouteInFlight else { return }
            if let last = lastRerouteOrigin, location.distance(from: last) < 150,
               !rerouteCoordinates.isEmpty { return }
            guard let target = rerouteJoinPoint() ?? remainingStops.first else { return }
            lastRerouteOrigin = location
            isRerouteInFlight = true
            let coord = location.coordinate
            rerouteTask = Task { await self.calculateReroute(from: coord, to: target) }
        } else {
            rerouteTask?.cancel()
            rerouteTask = nil
            isRerouteInFlight = false
            lastRerouteOrigin = nil
            if !rerouteCoordinates.isEmpty { rerouteCoordinates = [] }
        }
    }

    private func calculateReroute(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) async {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        req.transportType = .automobile
        if let route = try? await MKDirections(request: req).calculate().routes.first,
           !Task.isCancelled {
            rerouteCoordinates = route.polyline.coordinates
        }
        isRerouteInFlight = false
    }

    /// Advance `currentRouteSegmentIndex` to the closest upcoming segment, never backwards.
    private func advanceRouteProgress(to location: CLLocation) {
        guard routeCoordinates.count >= 2 else { return }
        let lookEnd = min(routeCoordinates.count - 2, currentRouteSegmentIndex + 200)
        guard lookEnd >= currentRouteSegmentIndex else { return }

        var minDist = Double.infinity
        var bestIdx = currentRouteSegmentIndex
        for i in currentRouteSegmentIndex...lookEnd {
            let d = distanceToLineSegment(from: location, a: routeCoordinates[i], b: routeCoordinates[i + 1])
            if d < minDist { minDist = d; bestIdx = i }
            if minDist < 5 { break }
        }
        // Only advance if user is actually near the route — prevents a far-away GPS fix
        // from jumping the index to the end of a short route, which caused the straight-line bug.
        if bestIdx > currentRouteSegmentIndex && minDist <= 80 {
            currentRouteSegmentIndex = bestIdx
        }
    }

    /// Minimum perpendicular distance to any segment in a window around the current progress index.
    private func minimumDistanceToUpcomingRoute(from location: CLLocation) -> Double {
        guard routeCoordinates.count >= 2 else { return 0 }
        let start = max(0, currentRouteSegmentIndex - 5)
        let end = min(routeCoordinates.count - 2, currentRouteSegmentIndex + 100)
        guard end >= start else { return 0 }

        var minDist = Double.infinity
        for i in start...end {
            let d = distanceToLineSegment(from: location, a: routeCoordinates[i], b: routeCoordinates[i + 1])
            if d < minDist { minDist = d }
            if minDist < 5 { return minDist }
        }
        return minDist
    }

    /// Perpendicular distance from `point` to segment A→B, clamped to the segment ends.
    private func distanceToLineSegment(from point: CLLocation, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double {
        // Project to a local flat-earth frame (degrees → approximate equal-scale units)
        let cosLat = cos(a.latitude * .pi / 180)
        let ax = a.longitude * cosLat, ay = a.latitude
        let bx = b.longitude * cosLat, by = b.latitude
        let px = point.coordinate.longitude * cosLat, py = point.coordinate.latitude

        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        let nearLat: Double, nearLng: Double
        if lenSq < 1e-18 {
            nearLat = a.latitude; nearLng = a.longitude
        } else {
            let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
            nearLat = a.latitude + t * (b.latitude - a.latitude)
            nearLng = a.longitude + t * (b.longitude - a.longitude)
        }
        return point.distance(from: CLLocation(latitude: nearLat, longitude: nearLng))
    }

    /// Walk ~500 m ahead on the planned route from the current progress point so the
    /// reroute leads the rider back to the actual planned road, not straight to the next stop.
    private func rerouteJoinPoint() -> CLLocationCoordinate2D? {
        guard routeCoordinates.count > currentRouteSegmentIndex + 1 else { return nil }
        var accumulated = 0.0
        for i in currentRouteSegmentIndex..<routeCoordinates.count - 1 {
            let a = CLLocation(latitude: routeCoordinates[i].latitude, longitude: routeCoordinates[i].longitude)
            let b = CLLocation(latitude: routeCoordinates[i + 1].latitude, longitude: routeCoordinates[i + 1].longitude)
            accumulated += a.distance(from: b)
            if accumulated >= 500 { return routeCoordinates[i + 1] }
        }
        return nil
    }

}

// MARK: - Main View

struct RideNavigationView: View {
    let rideId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = NavigationViewModel()

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRiderId: String? = nil
    @State private var showRegroup = false
    @State private var regroupReason: CoordinationOverlayView.RegroupReason? = nil
    @State private var isBroadcasting = false
    @State private var showEndError = false
    @State private var isFreeLooking: Bool = false
    @State private var lastInteractionDate: Date = .distantPast

    private var destinationName: String { appState.currentRide?.destinationName ?? "Destination" }

    private var navCameraDistance: Double {
        switch vm.mySpeedKmh {
        case ..<20:  return 400
        case ..<60:  return 700
        default:     return 1000
        }
    }

    var body: some View {
        coreView
            .sheet(isPresented: $showRegroup, onDismiss: { isBroadcasting = false }) {
                RegroupBottomSheet(
                    selectedReason: $regroupReason,
                    onBroadcast: { coordinate in
                        guard !isBroadcasting else { return }
                        isBroadcasting = true
                        vm.broadcastRegroup(reason: regroupReason, at: coordinate)
                        showRegroup = false
                    },
                    isBroadcasting: isBroadcasting
                )
                .presentationDetents([.large])
            }
            .onChange(of: vm.activeRegroup) { _, regroup in handleRegroupChanged(regroup) }
            .navigationDestination(isPresented: $vm.showSummary) {
                RideSummaryView(rideId: rideId, rideTitle: appState.currentRide?.title, isPostRide: true)
            }
            .alert("Couldn't End Ride", isPresented: $showEndError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.endError ?? "An error occurred.")
            }
            .onChange(of: vm.endError) { _, err in if err != nil { showEndError = true } }
    }

    private var coreView: some View {
        ZStack {
            mapLayer
            hudLayer
            rightStatPills
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            appState.isRideActive = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            appState.isRideActive = false
            UIApplication.shared.isIdleTimerDisabled = false
            vm.teardown()
        }
        .task { await loadAndSetup() }
        .onChange(of: vm.routeVersion) { _, _ in handleRouteVersionChanged() }
        .onChange(of: vm.locationTick) { old, _ in handleLocationTickChanged(wasZero: old == 0) }
    }

    // MARK: - Load

    private func loadAndSetup() async {
        let fetched = try? await APIClient.shared.getRide(rideId)
        let ride = fetched ?? appState.currentRide
        if let fetched { appState.currentRide = fetched }
        guard let ride else { return }
        let userId = clerk.user?.id ?? ""
        await vm.setup(rideId: rideId, ride: ride, myUserId: userId)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            if let coord = vm.userLocation {
                Annotation("", coordinate: coord, anchor: .center) {
                    ConvoyLocationPin(heading: vm.userHeading)
                }
            }

            if !vm.rerouteCoordinates.isEmpty {
                MapPolyline(coordinates: vm.rerouteCoordinates)
                    .stroke(
                        Color(red: 1.0, green: 0.6, blue: 0.15),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [10, 6])
                    )
            }

            if !vm.routeCoordinates.isEmpty {
                MapPolyline(coordinates: vm.routeCoordinates)
                    .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            ForEach(vm.riders.filter { !$0.isMe }) { rider in
                Annotation(rider.name, coordinate: rider.coordinate, anchor: .bottom) {
                    LiveRiderPin(rider: rider, isSelected: selectedRiderId == rider.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedRiderId = (selectedRiderId == rider.id) ? nil : rider.id
                            }
                        }
                }
            }

            ForEach(vm.middleWaypoints, id: \.order) { wp in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                    WaypointPin(name: wp.name)
                }
            }

            if let coord = vm.destinationCoordinate {
                Annotation("", coordinate: coord, anchor: .bottom) {
                    DestinationPin(name: destinationName)
                }
            }

            if let regroup = vm.activeRegroup {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: regroup.lat, longitude: regroup.lng), anchor: .bottom) {
                    RegroupPin(type: regroup.type)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .ignoresSafeArea()
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in onMapInteraction() }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { _ in onMapInteraction() }
        )
    }

    private func onMapInteraction() {
        lastInteractionDate = Date()
        if !isFreeLooking { isFreeLooking = true }
    }

    private func resumeNavigation() {
        isFreeLooking = false
        lastInteractionDate = .distantPast
        guard let coord = vm.userLocation else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: coord,
                distance: navCameraDistance,
                heading: vm.userHeading,
                pitch: 55
            ))
        }
    }

    private func handleRouteVersionChanged() {
        guard vm.locationTick == 0 else { return }
        if !vm.routeCoordinates.isEmpty {
            let poly = MKPolyline(coordinates: vm.routeCoordinates, count: vm.routeCoordinates.count)
            let padded = poly.boundingMapRect.insetBy(dx: -poly.boundingMapRect.width * 0.15, dy: -poly.boundingMapRect.height * 0.15)
            let region = MKCoordinateRegion(padded)
            let spanMeters = max(
                region.span.latitudeDelta * 111_000,
                region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)
            )
            cameraPosition = .camera(MapCamera(centerCoordinate: region.center, distance: spanMeters * 0.9, heading: 0, pitch: 0))
        } else if let dest = vm.destinationCoordinate {
            cameraPosition = .camera(MapCamera(centerCoordinate: dest, distance: 50_000, heading: 0, pitch: 0))
        }
    }

    private func handleLocationTickChanged(wasZero: Bool) {
        guard let coord = vm.userLocation else { return }
        let isMoving = vm.mySpeedKmh > 2.0
        let idleSeconds = Date().timeIntervalSince(lastInteractionDate)
        let shouldFollow = wasZero || (isMoving && idleSeconds >= 3.0)
        if isFreeLooking && shouldFollow { isFreeLooking = false }
        guard shouldFollow else { return }
        withAnimation(wasZero ? .easeInOut(duration: 1.5) : .linear(duration: 0.3)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: coord, distance: navCameraDistance, heading: vm.userHeading, pitch: 0))
        }
    }

    private func handleRegroupChanged(_ regroup: RegroupEvent?) {
        guard let regroup else { return }
        isFreeLooking = true
        lastInteractionDate = Date()
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: regroup.lat, longitude: regroup.lng),
                distance: 600,
                heading: 0,
                pitch: 0
            ))
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            resumeNavigation()
        }
    }

    // MARK: - HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            topBar

            if vm.isOffRoute {
                offRouteBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: vm.isOffRoute)
            }

            if vm.showSplitAlert {
                GroupSplitAlert(
                    onIgnore: { withAnimation(.spring()) { vm.showSplitAlert = false } },
                    onRegroup: { showRegroup = true }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(), value: vm.showSplitAlert)
            }

            if vm.showRegroupToast, let regroup = vm.activeRegroup {
                RegroupToastBanner(type: regroup.type)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: vm.showRegroupToast)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { vm.showRegroupToast = false }
                    }
            }

            if vm.showRegroupResolvedToast {
                RegroupResolvedBanner()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: vm.showRegroupResolvedToast)
            }

            Spacer()

            if isFreeLooking {
                Button(action: resumeNavigation) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("RESUME")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.2)
                    }
                    .foregroundColor(Color.onPrimaryFixed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.primaryFixed)
                    .clipShape(Capsule())
                    .shadow(color: Color.primaryFixed.opacity(0.55), radius: 10)
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.35), value: isFreeLooking)
                .padding(.bottom, 8)
            }

            if vm.activeRegroup != nil {
                arrivedButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: vm.activeRegroup != nil)
            }

            bottomControls
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.primaryFixed)
                        Text(vm.myRank > 0 ? "RANK \(vm.myRank)" : "RANK --")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))

                    HStack(spacing: 7) {
                        Circle().fill(Color.primaryFixed).frame(width: 7, height: 7)
                            .shadow(color: Color.primaryFixed, radius: 5)
                        Text(vm.riderCount > 0 ? "\(vm.riderCount) RIDERS LIVE" : "-- RIDERS LIVE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)

            leaderboardStrip
        }
        .padding(.top, 8)
    }

    private func maneuverIcon(for instruction: String) -> String {
        let l = instruction.lowercased()
        if l.contains("arrive") || l.contains("destination") { return "flag.checkered" }
        if l.contains("u-turn") || l.contains("uturn") { return "arrow.uturn.left" }
        if l.contains("left") { return "arrow.turn.up.left" }
        if l.contains("right") { return "arrow.turn.up.right" }
        if l.contains("merge") { return "arrow.merge" }
        if l.contains("roundabout") || l.contains("rotary") { return "arrow.triangle.turn.up.right.circle" }
        return "arrow.up"
    }

    private var leaderboardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if vm.leaderboardRows.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.surfaceContainerHigh.opacity(0.5))
                                .frame(width: 140, height: 56)
                                .redacted(reason: .placeholder)
                        }
                    } else {
                        ForEach(vm.leaderboardRows) { row in
                            LiveLeaderboardCard(row: row, isSelected: selectedRiderId == row.id)
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedRiderId) { _, id in
                if let id {
                    withAnimation(.spring(response: 0.4)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var offRouteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.errorColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("OFF ROUTE")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(Color.errorColor)
                    .tracking(1.5)
                Text("Rerouting to next stop")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.errorColor.opacity(0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.errorContainer.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                regroupButton
                endRideButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.surfaceDim.opacity(0.65), Color.surfaceDim.opacity(0.97)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var regroupButton: some View {
        Button(action: { showRegroup = true }) {
            VStack(spacing: 5) {
                Image(systemName: "person.3.fill").font(.system(size: 19))
                Text("REGROUP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
            }
            .foregroundColor(Color.onSurface)
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(Color.surfaceContainerHigh.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        }
    }

    private var endRideButton: some View {
        Button(action: {
            if vm.amILeader {
                Task { await vm.endRide() }
            } else {
                dismiss()
            }
        }) {
            VStack(spacing: 5) {
                if vm.isEnding {
                    ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                } else {
                    Image(systemName: "stop.fill").font(.system(size: 19))
                }
                Text(vm.amILeader ? "END RIDE" : "LEAVE RIDE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
            }
            .foregroundColor(Color.errorColor)
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(Color.errorContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
        }
        .disabled(vm.isEnding)
    }

    // MARK: - Arrived Button

    private var arrivedButton: some View {
        Button(action: {
            if !vm.hasMarkedArrived { vm.markArrivedAtRegroup() }
        }) {
            HStack(spacing: 10) {
                Image(systemName: vm.hasMarkedArrived ? "clock.fill" : "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text(vm.hasMarkedArrived ? "WAITING FOR OTHERS..." : "MARK AS ARRIVED")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(vm.hasMarkedArrived ? Color.onSurfaceVariant : Color.onPrimaryFixed)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(vm.hasMarkedArrived ? Color.surfaceContainerHigh : Color.primaryFixed)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                vm.hasMarkedArrived ? Color.outlineVariant.opacity(0.4) : Color.clear,
                lineWidth: 1
            ))
        }
        .disabled(vm.hasMarkedArrived)
        .animation(.spring(response: 0.3), value: vm.hasMarkedArrived)
    }

    // MARK: - Right Stat Pills

    private var rightStatPills: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 9) {
                    NavStatPill(
                        label: "SPEED",
                        value: vm.mySpeedKmh > 0 ? String(format: "%.0f", vm.mySpeedKmh) : "--",
                        unit: "KM/H"
                    )
                    NavStatPill(label: "ETA", value: vm.etaString, unit: nil)
                    NavStatPill(
                        label: "DIST",
                        value: vm.myDistanceToGoalKm > 0 ? String(format: "%.1f", vm.myDistanceToGoalKm) : "--",
                        unit: "KM"
                    )
                    if !vm.currentInstruction.isEmpty {
                        turnPill
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.4), value: vm.currentInstruction)
                    }
                }
                .padding(.trailing, 14)
            }
            Spacer()
        }
        .padding(.top, 180)
        .padding(.bottom, 220)
    }

    private var turnPill: some View {
        let dist = vm.distanceToNextTurnMeters
        let distText = dist >= 1000
            ? String(format: "%.1fkm", dist / 1000)
            : String(format: "%.0fm", dist)

        return VStack(spacing: 4) {
            Image(systemName: maneuverIcon(for: vm.currentInstruction))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.primaryFixed)
            if dist > 0 {
                Text("in \(distText)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.onSurface)
                    .lineLimit(1)
            }
        }
        .frame(width: 72, height: dist > 0 ? 56 : 44)
        .background(Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primaryFixed.opacity(0.45), lineWidth: 1.5)
        )
    }
}

// MARK: - Live Rider Pin

struct LiveRiderPin: View {
    let rider: LiveRider
    let isSelected: Bool

    private var size: CGFloat { isSelected ? 54 : 46 }
    private var firstName: String { rider.name.components(separatedBy: " ").first ?? rider.name }
    private var borderColor: Color {
        isSelected ? Color.primaryFixed : (rider.isMe ? Color.primaryFixed : Color.white.opacity(0.9))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // White backing so the photo reads clearly on any map tile colour
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)

                // Profile photo fills the circle; letter fallback shown while loading or if no URL
                if let url = rider.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            letterFallback
                        }
                    }
                    .frame(width: size - 4, height: size - 4)
                    .clipShape(Circle())
                } else {
                    letterFallback
                        .frame(width: size - 4, height: size - 4)
                }

                // Coloured border ring on top
                Circle()
                    .stroke(borderColor, lineWidth: isSelected ? 3 : 2.5)
                    .frame(width: size, height: size)

                // Rank badge
                Text("#\(rider.rank)")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundColor(rider.rank == 1 ? Color.onPrimaryFixed : Color.onSurface)
                    .padding(.horizontal, 3).padding(.vertical, 1.5)
                    .background(rider.rank == 1 ? Color.primaryFixed : Color.surfaceContainerHighest.opacity(0.95))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 4, y: 4)
                    .frame(width: size, height: size)
            }
            .shadow(color: isSelected ? Color.primaryFixed.opacity(0.55) : Color.black.opacity(0.3),
                    radius: isSelected ? 12 : 5, y: 2)

            Triangle()
                .fill(Color.white)
                .frame(width: 10, height: 6)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .offset(y: -1)

            // Name label always visible — first name only unless selected
            Text(isSelected ? rider.name.uppercased() : firstName.uppercased())
                .font(.system(size: isSelected ? 9 : 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, isSelected ? 8 : 6)
                .padding(.vertical, isSelected ? 4 : 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    isSelected ? Color.primaryFixed.opacity(0.6) : Color.outlineVariant.opacity(0.3),
                    lineWidth: 1
                ))
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var letterFallback: some View {
        Circle()
            .fill(Color.surfaceContainerHigh)
            .overlay(
                Text(String(rider.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundColor(rider.isMe ? Color.primaryFixed : Color.onSurface)
            )
    }
}

// MARK: - Live Leaderboard Card

struct LiveLeaderboardCard: View {
    let row: NavLeaderboardRow
    var isSelected: Bool = false

    private var isHighlighted: Bool { row.rank == 1 || isSelected || row.isMe }
    private var firstName: String { row.name.components(separatedBy: " ").first ?? row.name }
    private var lastName: String {
        let parts = row.name.components(separatedBy: " ")
        return parts.dropFirst().joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 7) {
            Text("\(row.rank)")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurfaceVariant)
                .frame(width: 18)

            Group {
                if let url = row.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Circle().fill(Color.surfaceVariant) }
                } else {
                    Circle().fill(Color.surfaceVariant)
                        .overlay(
                            Text(String(row.name.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurface)
                        )
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().stroke(
                isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.4),
                lineWidth: isHighlighted ? 2 : 1
            ))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(firstName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                    if row.isMe {
                        Text("YOU")
                            .font(.system(size: 6, weight: .black, design: .monospaced))
                            .foregroundColor(Color.onPrimaryFixed)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Color.primaryFixed).clipShape(Capsule())
                    }
                }
                if !lastName.isEmpty {
                    Text(lastName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isHighlighted ? Color.primaryFixed.opacity(0.12) : Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.3),
            lineWidth: isHighlighted ? 1.5 : 1
        ))
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Destination Pin

// MARK: - Convoy Location Pin

struct ConvoyLocationPin: View {
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primaryFixed.opacity(0.22))
                .frame(width: 46, height: 46)
            Circle()
                .fill(Color.primaryFixed)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: Color.primaryFixed.opacity(0.9), radius: 10)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.onPrimaryFixed)
                .offset(y: -1)
        }
        .rotationEffect(.degrees(heading))
    }
}

// MARK: - Waypoint Pin

struct WaypointPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.surfaceContainerHighest)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.tertiaryFixed, lineWidth: 2))
                    .shadow(color: Color.tertiaryFixed.opacity(0.4), radius: 6)
                Image(systemName: "mappin")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.tertiaryFixed)
            }
            Triangle().fill(Color.tertiaryFixed).frame(width: 8, height: 5).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Destination Pin

struct DestinationPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(Color.primaryFixed).frame(width: 44, height: 44)
                    .shadow(color: Color.primaryFixed.opacity(0.7), radius: 12)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }
            Triangle().fill(Color.primaryFixed).frame(width: 10, height: 6).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Start Pin

struct StartPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceContainerHighest)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                .shadow(color: Color.primaryFixed.opacity(0.3), radius: 8)
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.primaryFixed)
        }
    }
}

// MARK: - Nav Stat Pill

struct NavStatPill: View {
    let label: String
    let value: String
    let unit: String?
    var accentColor: Color? = nil

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.onSurfaceVariant).tracking(1)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(accentColor ?? Color.onSurface)
            if let unit {
                Text(unit).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Color.onSurfaceVariant)
            } else {
                Text(" ").font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Regroup Pin

struct RegroupPin: View {
    let type: String

    private var icon: String {
        switch type {
        case "FUEL":   return "fuelpump.fill"
        case "FOOD":   return "fork.knife"
        case "SCENIC": return "camera.fill"
        default:       return "hand.raised.fill"
        }
    }

    private var accentColor: Color {
        switch type {
        case "FUEL":   return Color(red: 1.0, green: 0.63, blue: 0.0)   // amber
        case "FOOD":   return Color(red: 1.0, green: 0.43, blue: 0.0)   // orange
        case "SCENIC": return Color(red: 0.01, green: 0.61, blue: 0.9)  // sky blue
        default:       return Color(red: 0.48, green: 0.11, blue: 0.64) // purple
        }
    }

    private var label: String {
        switch type {
        case "FUEL":   return "FUEL STOP"
        case "FOOD":   return "FOOD STOP"
        case "SCENIC": return "SCENIC STOP"
        default:       return "STOP"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.surfaceDim)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(accentColor, lineWidth: 2.5))
                    .shadow(color: accentColor.opacity(0.5), radius: 8)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(accentColor)
            }
            Triangle().fill(accentColor).frame(width: 8, height: 5).offset(y: -1)
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Regroup Toast Banner

struct RegroupToastBanner: View {
    let type: String

    private var icon: String {
        switch type {
        case "FUEL":   return "fuelpump.fill"
        case "FOOD":   return "fork.knife"
        case "SCENIC": return "camera.fill"
        default:       return "hand.raised.fill"
        }
    }

    private var accentColor: Color {
        switch type {
        case "FUEL":   return Color(red: 1.0, green: 0.63, blue: 0.0)
        case "FOOD":   return Color(red: 1.0, green: 0.43, blue: 0.0)
        case "SCENIC": return Color(red: 0.01, green: 0.61, blue: 0.9)
        default:       return Color(red: 0.48, green: 0.11, blue: 0.64)
        }
    }

    private var label: String {
        switch type {
        case "FUEL":   return "Fuel Stop"
        case "FOOD":   return "Food Stop"
        case "SCENIC": return "Scenic Stop"
        default:       return "Stop"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("REGROUP CALLED")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(accentColor)
                    .tracking(1)
                Text("Head to the \(label)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.onSurface)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.5), lineWidth: 1.5))
    }
}

// MARK: - Regroup Resolved Banner

struct RegroupResolvedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.tertiaryFixed)
                .frame(width: 36, height: 36)
                .background(Color.tertiaryFixed.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Regroup complete · Everyone arrived")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.tertiaryFixed)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.tertiaryFixed.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.tertiaryFixed.opacity(0.5), lineWidth: 1.5))
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    NavigationStack {
        RideNavigationView(rideId: "preview")
            .environmentObject(AppState())
            .environment(Clerk.shared)
    }
}
