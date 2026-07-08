import SwiftUI
import ClerkKit
import Combine
import CoreLocation

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
    @Published var activeRouteCoordinates: [CLLocationCoordinate2D] = []   // trimmed to user position
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
    private var regroupResolvedToastTask: Task<Void, Never>? = nil
    private var isRerouteInFlight = false
    private var lastRerouteOrigin: CLLocation? = nil
    private var needsInitialRouteCheck = false   // bypasses off-route debounce on first GPS fix
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

        if needsInitialRouteCheck && !routeCoordinates.isEmpty {
            needsInitialRouteCheck = false
            if minimumDistanceToUpcomingRoute(from: location) > offRouteThresholdMeters,
               !isRerouteInFlight {
                isOffRoute = true
                consecutiveOffCount = offRouteConfirmCount
                lastRerouteOrigin = location
                let coord = location.coordinate
                Task { await calculateFullReroute(from: coord) }
            }
        }

        if !isOffRoute { trimActiveRoute(to: location) }

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

        var allCoords: [CLLocationCoordinate2D] = []
        var totalTime: TimeInterval = 0
        var steps: [NavStep] = []

        for i in 0..<sorted.count - 1 {
            let origin = CLLocationCoordinate2D(latitude: sorted[i].lat,   longitude: sorted[i].lng)
            let dest   = CLLocationCoordinate2D(latitude: sorted[i+1].lat, longitude: sorted[i+1].lng)
            guard let result = try? await GoogleDirectionsService.route(from: origin, to: dest) else { continue }
            allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
            totalTime += result.durationSeconds
            for step in result.steps {
                guard !step.instruction.isEmpty else { continue }
                steps.append(NavStep(instruction: step.instruction, endCoordinate: step.endCoordinate, distanceMeters: step.distanceMeters))
            }
        }

        navSteps = steps
        currentStepIndex = 0
        if let first = navSteps.first {
            currentInstruction       = first.instruction
            distanceToNextTurnMeters = first.distanceMeters
        }
        routeCoordinates         = allCoords
        activeRouteCoordinates   = allCoords   // full route until first GPS update trims it
        routeExpectedTravelTime  = totalTime
        currentRouteSegmentIndex = 0
        consecutiveOffCount      = 0
        consecutiveOnCount       = 0
        needsInitialRouteCheck   = true
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
            guard !isRerouteInFlight else { return }
            // Throttle: only recalculate every 200 m of travel while off-route.
            if let last = lastRerouteOrigin, location.distance(from: last) < 200 { return }
            lastRerouteOrigin = location
            let coord = location.coordinate
            Task { await self.calculateFullReroute(from: coord) }
        } else {
            isRerouteInFlight = false
            lastRerouteOrigin = nil
        }
    }

    /// Recalculates the full remaining route from the user's current position through
    /// all remaining stops to the destination, writing the result into activeRouteCoordinates.
    /// The original routeCoordinates is never touched — it stays as the dim planned-route layer.
    private func calculateFullReroute(from origin: CLLocationCoordinate2D) async {
        guard !remainingStops.isEmpty else { return }
        isRerouteInFlight = true
        let stops = [origin] + remainingStops
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<stops.count - 1 {
            guard let result = try? await GoogleDirectionsService.route(
                from: stops[i], to: stops[i + 1], trafficAware: false
            ) else { continue }
            coords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
        }
        isRerouteInFlight = false
        guard !coords.isEmpty else { return }
        activeRouteCoordinates = coords
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

    /// Projects the user onto the current segment and rebuilds activeRouteCoordinates
    /// so the bright polyline starts exactly at the user's position.
    /// Only called when on-route; off-route uses calculateFullReroute instead.
    private func trimActiveRoute(to location: CLLocation) {
        guard routeCoordinates.count >= 2 else { return }
        let i    = currentRouteSegmentIndex
        let next = min(i + 1, routeCoordinates.count - 1)
        let a    = routeCoordinates[i]
        let b    = routeCoordinates[next]

        // Project onto segment using the same flat-earth frame as distanceToLineSegment.
        let cosLat = cos(a.latitude * .pi / 180)
        let ax = a.longitude * cosLat, ay = a.latitude
        let bx = b.longitude * cosLat, by = b.latitude
        let px = location.coordinate.longitude * cosLat, py = location.coordinate.latitude
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        let projected: CLLocationCoordinate2D
        if lenSq < 1e-18 {
            projected = a
        } else {
            let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
            projected = CLLocationCoordinate2D(
                latitude:  a.latitude  + t * (b.latitude  - a.latitude),
                longitude: a.longitude + t * (b.longitude - a.longitude)
            )
        }

        var trimmed: [CLLocationCoordinate2D] = [projected]
        if next < routeCoordinates.count {
            trimmed.append(contentsOf: routeCoordinates[next...])
        }
        activeRouteCoordinates = trimmed
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


}

// MARK: - Main View

struct RideNavigationView: View {
    let rideId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = NavigationViewModel()

    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var cameraCommand: MapCameraCommand? = nil
    @State private var selectedRiderId: String? = nil
    @State private var showRegroup = false
    @State private var regroupReason: CoordinationOverlayView.RegroupReason? = nil
    @State private var isBroadcasting = false
    @State private var showEndError = false
    @State private var isFreeLooking: Bool = false
    @State private var lastInteractionDate: Date = .distantPast
    @State private var isNavigationActive: Bool = false

    private var isLandscape: Bool { vSizeClass == .compact }

    private var destinationName: String { appState.currentRide?.destinationName ?? "Destination" }

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
            ConvoTrackAppDelegate.landscapeAllowed = true
        }
        .onDisappear {
            appState.isRideActive = false
            UIApplication.shared.isIdleTimerDisabled = false
            ConvoTrackAppDelegate.landscapeAllowed = false
            vm.teardown()
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                scene.requestGeometryUpdate(prefs) { _ in }
            }
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

    private var navMapPins: [MapPin] {
        var pins: [MapPin] = []
        if let coord = vm.userLocation {
            pins.append(MapPin(id: "me", coordinate: coord, style: .userLocation(heading: vm.userHeading), anchorBottom: false))
        }
        for rider in vm.riders.filter({ !$0.isMe }) {
            pins.append(MapPin(id: rider.id, coordinate: rider.coordinate,
                               style: .rider(name: rider.name, avatarUrl: rider.avatarUrl,
                                             isMe: false, rank: rider.rank,
                                             isSelected: selectedRiderId == rider.id)))
        }
        for wp in vm.middleWaypoints {
            pins.append(MapPin(id: "wp_\(wp.order)", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .waypoint(name: wp.name)))
        }
        if let coord = vm.destinationCoordinate {
            pins.append(MapPin(id: "dest", coordinate: coord, style: .destination(name: destinationName)))
        }
        if let regroup = vm.activeRegroup {
            pins.append(MapPin(id: "regroup", coordinate: CLLocationCoordinate2D(latitude: regroup.lat, longitude: regroup.lng), style: .regroup(type: regroup.type)))
        }
        return pins
    }

    private var mapLayer: some View {
        GoogleMapView(
            routeCoords:         vm.activeRouteCoordinates,
            originalRouteCoords: vm.routeCoordinates,
            stopCoords:          navStopCoords,
            pins:          navMapPins,
            cameraCommand: cameraCommand,
            isInteractive: true,
            onInteraction: onMapInteraction
        )
        .ignoresSafeArea()
    }

    private var navStopCoords: [CLLocationCoordinate2D] {
        guard let ride = appState.currentRide else { return [] }
        return ride.waypoints.sorted { $0.order < $1.order }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    private func onMapInteraction() {
        lastInteractionDate = Date()
        if !isFreeLooking { isFreeLooking = true }
    }

    private var navZoom: Float {
        switch vm.mySpeedKmh {
        case ..<20:  return 17.5
        case ..<60:  return 16.5
        default:     return 16.0
        }
    }

    private let navTilt: Double = 45

    private func resumeNavigation() {
        isFreeLooking = false
        lastInteractionDate = .distantPast
        guard let coord = vm.userLocation else { return }
        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: true)
        )
    }

    private func beginNavigation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isNavigationActive = true }
        guard let coord = vm.userLocation else { return }
        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: true)
        )
    }

    private func handleRouteVersionChanged() {
        guard !isNavigationActive else { return }
        if !vm.routeCoordinates.isEmpty {
            // Extra bottom inset accounts for the navigation preview bar that sits over the map.
            cameraCommand = MapCameraCommand.fitRouteInsets(
                vm.routeCoordinates, top: 80, left: 44, bottom: 200, right: 44, animated: true
            )
        } else if let dest = vm.destinationCoordinate {
            cameraCommand = MapCameraCommand.focus(lat: dest.latitude, lng: dest.longitude, zoom: 11)
        }
    }

    private func handleLocationTickChanged(wasZero: Bool) {
        guard let coord = vm.userLocation else { return }
        guard isNavigationActive else { return }
        let isMoving    = vm.mySpeedKmh > 2.0
        let idleSeconds = Date().timeIntervalSince(lastInteractionDate)
        let shouldFollow = wasZero || (isMoving && idleSeconds >= 3.0)
        if isFreeLooking && shouldFollow { isFreeLooking = false }
        guard shouldFollow else { return }
        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: !wasZero)
        )
    }

    private func handleRegroupChanged(_ regroup: RegroupEvent?) {
        guard let regroup else { return }
        isFreeLooking = true
        lastInteractionDate = Date()
        cameraCommand = MapCameraCommand.focus(lat: regroup.lat, lng: regroup.lng, zoom: 15)
        Task {
            try? await Task.sleep(for: .seconds(5))
            resumeNavigation()
        }
    }

    // MARK: - HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            topBar

            if isNavigationActive {
                if vm.isOffRoute {
                    HStack {
                        offRouteBanner
                        Spacer()
                    }
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
            }

            Spacer()

            if isFreeLooking && isNavigationActive {
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

            if vm.activeRegroup != nil && isNavigationActive {
                arrivedButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: vm.activeRegroup != nil)
            }

            if isNavigationActive {
                bottomControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                navigationPreviewBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isNavigationActive)
    }

    private var navigationPreviewBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.outlineVariant.opacity(0.25))

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destinationName.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                        .tracking(0.3)
                    Text(vm.myDistanceToGoalKm > 0
                         ? String(format: "%.1f km away", vm.myDistanceToGoalKm)
                         : "Calculating route...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.onSurfaceVariant)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(vm.etaString)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(Color.onSurface)
                    Text("ETA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurfaceVariant)
                        .tracking(1.5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Button(action: beginNavigation) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text("START NAVIGATION")
                        .font(.headlineMd)
                        .tracking(-0.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.primaryFixed)
                .foregroundColor(Color.onPrimaryFixed)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.primaryFixed.opacity(0.4), radius: 16, y: 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, isLandscape ? 8 : 44)
        }
        .background(Color.surfaceDim)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                }

                if isNavigationActive {
                    turnInstructionCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                    if isLandscape {
                        landscapeLeaderboardStrip
                            .transition(.opacity)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onSurfaceVariant)
                            .tracking(1.5)
                        Text(destinationName)
                            .font(.bodyLg)
                            .foregroundColor(Color.onSurface)
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                    Spacer()
                }

                if isNavigationActive {
                    HStack(spacing: 6) {
                        Circle().fill(Color.primaryFixed).frame(width: 6, height: 6)
                            .shadow(color: Color.primaryFixed, radius: 4)
                        Text(vm.riderCount > 0 ? "\(vm.riderCount)" : "--")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.35), value: isNavigationActive)

            if isNavigationActive && !isLandscape {
                leaderboardStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.35), value: isNavigationActive)
    }

    private var turnInstructionCard: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primaryFixed)
                    .frame(width: 36, height: 36)
                Image(systemName: vm.currentInstruction.isEmpty
                      ? "arrow.up"
                      : maneuverIcon(for: vm.currentInstruction))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }

            VStack(alignment: .leading, spacing: 1) {
                let dist = vm.distanceToNextTurnMeters
                let distText: String = {
                    if dist <= 0 { return "" }
                    return dist >= 1000
                        ? String(format: "%.1f km", dist / 1000)
                        : String(format: "%.0f m", dist)
                }()
                if !distText.isEmpty {
                    Text(distText)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(Color.primaryFixed)
                }
                Text(vm.currentInstruction.isEmpty ? "Follow route" : vm.currentInstruction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.onSurface)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primaryFixed.opacity(0.3), lineWidth: 1))
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

    // Compact inline leaderboard for the landscape top bar — same height as the turn card.
    private var landscapeLeaderboardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if vm.leaderboardRows.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.surfaceContainerHigh.opacity(0.5))
                                .frame(width: 100, height: 44)
                                .redacted(reason: .placeholder)
                        }
                    } else {
                        ForEach(vm.leaderboardRows) { row in
                            LiveLeaderboardCard(row: row, isSelected: selectedRiderId == row.id)
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: selectedRiderId) { _, id in
                if let id {
                    withAnimation(.spring(response: 0.4)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var offRouteBanner: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text("OFF ROUTE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(Color.errorColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.errorContainer.opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.errorColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            if isLandscape {
                HStack(spacing: 8) {
                    Spacer()
                    regroupButton
                    endRideButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    regroupButton
                    endRideButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.surfaceDim.opacity(0.65), Color.surfaceDim.opacity(0.97)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var buttonSize: CGFloat { isLandscape ? 44 : 56 }

    private var regroupButton: some View {
        Button(action: { showRegroup = true }) {
            Image(systemName: "person.3.fill")
                .font(.system(size: isLandscape ? 16 : 20))
                .foregroundColor(Color.onSurface)
                .frame(width: buttonSize, height: buttonSize)
                .background(Color.surfaceContainerHigh.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
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
            Group {
                if vm.isEnding {
                    ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: isLandscape ? 16 : 20))
                }
            }
            .foregroundColor(Color.errorColor)
            .frame(width: buttonSize, height: buttonSize)
            .background(Color.errorContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
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
                if isNavigationActive {
                    VStack(spacing: isLandscape ? 6 : 9) {
                        NavStatPill(
                            label: "SPEED",
                            value: vm.mySpeedKmh > 0 ? String(format: "%.0f", vm.mySpeedKmh) : "--",
                            unit: "KM/H",
                            compact: isLandscape
                        )
                        NavStatPill(label: "ETA", value: vm.etaString, unit: nil, compact: isLandscape)
                        NavStatPill(
                            label: "DIST",
                            value: vm.myDistanceToGoalKm > 0 ? String(format: "%.1f", vm.myDistanceToGoalKm) : "--",
                            unit: "KM",
                            compact: isLandscape
                        )
                    }
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                }
            }
            Spacer()
        }
        .padding(.top, isLandscape ? 56 : 180)
        .padding(.bottom, isLandscape ? 72 : 220)
        .animation(.easeInOut(duration: 0.4), value: isNavigationActive)
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

// MARK: - ConvoTrack Location Pin

struct ConvoTrackLocationPin: View {
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
    var compact: Bool = false

    private var size: CGFloat { compact ? 56 : 72 }

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.onSurfaceVariant).tracking(1)
            Text(value)
                .font(.system(size: compact ? 13 : 17, weight: .black, design: .monospaced))
                .foregroundColor(accentColor ?? Color.onSurface)
            if let unit {
                Text(unit).font(.system(size: compact ? 7 : 8, weight: .medium, design: .monospaced)).foregroundColor(Color.onSurfaceVariant)
            } else {
                Text(" ").font(.system(size: compact ? 7 : 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: size, height: size)
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
