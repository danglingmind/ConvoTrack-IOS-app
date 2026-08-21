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
    @Published var onlineUserIds: Set<String> = []   // authoritative presence for offline markers
    @Published var connectionState: RideRealtimeSession.ConnectionState = .connected
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
    /// Live remaining travel time to the next stop. Refreshed from the traffic-aware Routes API
    /// and counted down in between, so it moves every second and reacts to traffic — unlike the
    /// planned-duration estimate it supersedes, which could only change when distance changed and
    /// always assumed the pace the route was planned at.
    @Published var etaSecondsRemaining: TimeInterval? = nil
    @Published var currentInstruction: String = ""
    /// Routes API maneuver for the current step (`TURN_LEFT`, `ROUNDABOUT_RIGHT`, …). Drives the
    /// banner arrow, so the arrow can't disagree with the instruction text.
    @Published var currentManeuver: String = ""
    @Published var distanceToNextTurnMeters: Double = 0
    @Published var isOffRoute: Bool = false
    @Published var activeRegroup: RegroupEvent? = nil
    @Published var hasMarkedArrived: Bool = false
    @Published var showRegroupToast: Bool = false
    @Published var showRegroupResolvedToast: Bool = false
    @Published var activeEmergency: EmergencyEvent? = nil

    var amILeader: Bool { !myUserId.isEmpty && myUserId == leaderId }

    /// True while a real turn instruction is still ahead (not yet at the final
    /// step / destination). Drives the maneuver-aware camera pull-back.
    var hasUpcomingTurn: Bool { currentStepIndex < navSteps.count - 1 && !currentInstruction.isEmpty }

    /// Only the rider who raised the emergency or the ride leader may clear it (server enforces the
    /// same rule); everyone else sees the persistent pin + siren until one of them dismisses it.
    var canDismissEmergency: Bool {
        guard let e = activeEmergency else { return false }
        return e.userId == myUserId || amILeader
    }

    /// Live rider count for the top-bar dot. Uses the SAME presence rule as the leaderboard rows
    /// (self is always live; every other rider must have a current heartbeat in `onlineUserIds`),
    /// so the number can never disagree with the greyed-out rows. Derived from the roster +
    /// presence rather than the fluctuating `ride:state_update` participant array, which only
    /// carries riders that have posted a location tick.
    var liveRiderCount: Int {
        leaderboardRows.filter { $0.isMe || onlineUserIds.contains($0.id) }.count
    }

    var emergencyReporterName: String {
        guard let e = activeEmergency else { return "" }
        if e.userId == myUserId { return "You" }
        return leaderboardRows.first { $0.id == e.userId }?.name
            ?? staticParticipants.first { $0.userId == e.userId }?.name
            ?? "A rider"
    }

    /// Remaining travel time (not clock arrival) to the NEXT stop on the route. On a single-stop
    /// ride the next stop is the destination; on a multi-stop ride it's the upcoming waypoint.
    /// Formatted in hours once ≥ 60 min, minutes below that.
    var etaString: String {
        // Live traffic-aware value when we have one; the planned-duration estimate below is only
        // the bootstrap for the seconds before the first refresh lands.
        if let live = etaSecondsRemaining { return Self.formatDuration(live) }
        guard routeExpectedTravelTime > 0, totalDistanceMeters > 0, myDistanceToGoalKm >= 0 else { return "--" }
        let remainingFraction = min(1, max(0, (myDistanceToGoalKm * 1000) / totalDistanceMeters))
        let elapsedSecs = routeExpectedTravelTime * (1 - remainingFraction)

        let secsToNextStop: TimeInterval
        if !stopCumulativeDurations.isEmpty {
            // How many stops we've already passed → index of the next one.
            let passed = max(0, totalStopCount - remainingStops.count)
            let idx = min(passed, stopCumulativeDurations.count - 1)
            secsToNextStop = max(0, stopCumulativeDurations[idx] - elapsedSecs)
        } else {
            secsToNextStop = routeExpectedTravelTime * remainingFraction
        }
        return Self.formatDuration(secsToNextStop)
    }

    /// "45m", "1h", "2h 15m" — hours once ≥ 60 min, minutes below.
    static func formatDuration(_ secs: TimeInterval) -> String {
        let totalMins = max(0, Int((secs / 60).rounded()))
        if totalMins < 60 { return "\(totalMins)m" }
        let h = totalMins / 60, m = totalMins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private struct NavStep {
        let instruction: String
        let maneuver: String?
        let endCoordinate: CLLocationCoordinate2D
        let distanceMeters: Double
        /// Distance from the route's start to this step's end, measured ALONG the drawn polyline.
        /// This is what makes step tracking self-correcting: it is compared against the rider's own
        /// along-route progress, so driving past a junction advances the step by itself.
        var endDistanceAlongRoute: Double
    }

    private var rideId = ""
    private var staticParticipants: [RideParticipant] = []
    private var myUserId = ""
    private var leaderId = ""
    private var totalDistanceMeters: Double = 0
    private var routeExpectedTravelTime: TimeInterval = 0
    private var navSteps: [NavStep] = []
    private var currentStepIndex: Int = 0
    /// Prefix distances along `navRoute` — `[i]` is metres from the start to vertex `i`. Rebuilt
    /// with the route (including on reroute); lets progress and step positions share one frame.
    private var navRouteCumulative: [Double] = []
    /// Last traffic-aware figure and when it was taken; `etaSecondsRemaining` is derived by
    /// subtracting elapsed time from these between refreshes.
    private var etaBaseSeconds: TimeInterval? = nil
    private var etaBaseDate: Date = .distantPast
    private var lastEtaRefresh: Date = .distantPast
    private var isEtaRefreshInFlight = false
    /// One Routes API call per rider per minute while navigating. Frequent enough that a jam is
    /// reflected quickly, rare enough not to be a per-second billing drain.
    private static let etaRefreshInterval: TimeInterval = 60
    private var lastBroadcastDate: Date = .distantPast
    private var lastCameraTickDate: Date = .distantPast
    private var remainingStops: [CLLocationCoordinate2D] = []
    // Cumulative travel time from the ride start to each stop (WAYPOINT/DESTINATION), in route order.
    // `totalStopCount` is the count captured at route-calc time; `remainingStops` shrinks as stops are
    // passed, so `totalStopCount - remainingStops.count` yields the index of the next stop.
    private var stopCumulativeDurations: [TimeInterval] = []
    private var totalStopCount: Int = 0
    private var regroupResolvedToastTask: Task<Void, Never>? = nil
    private var emergencySirenTimer: Timer? = nil
    // Last-known map position for every rider, kept so a rider who goes offline stays pinned at
    // their final spot (dimmed) instead of vanishing when they stop posting location ticks.
    private var lastKnownRiderPositions: [String: CLLocationCoordinate2D] = [:]
    private var isRerouteInFlight = false
    private var lastRerouteOrigin: CLLocation? = nil
    private var needsInitialRouteCheck = false   // bypasses off-route debounce on first GPS fix
    private let offRouteThresholdMeters: Double = 40
    /// The polyline the rider is actually following: the planned route at first, and the reroute
    /// once one lands. Progress, off-route detection, polyline trimming and step positions are all
    /// measured against THIS. `routeCoordinates` keeps its separate meaning — the dim planned
    /// layer, which a reroute deliberately never touches — so navigation must not measure itself
    /// against a plan the rider has already abandoned.
    private var navRoute: [CLLocationCoordinate2D] = []
    /// Forward-only progress index into `navRoute`.
    private var navSegmentIndex: Int = 0
    private var consecutiveOffCount: Int = 0
    private var consecutiveOnCount: Int = 0
    private let offRouteConfirmCount = 3   // consecutive off-route readings before flagging
    private let onRouteClearCount = 4      // consecutive on-route readings before clearing
    private var cancellables = Set<AnyCancellable>()

    func setup(rideId: String, ride: Ride, myUserId: String, session: RideRealtimeSession) async {
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
        if let myRow = leaderboardRows.first(where: { $0.isMe }) {
            myRank = myRow.rank
            myDistanceToGoalKm = ride.distanceMeters / 1000
        }

        await calculateRoute(from: ride.waypoints, polyline: ride.routePolyline)

        bind(to: session)

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

    /// Observe the shared `RideRealtimeSession` instead of subscribing to `SocketClient` directly.
    /// The session owns the connection, reconnect→rejoin, heartbeat and presence for the whole ride,
    /// so navigation self-heals after a drop and sees an always-fresh roster (mid-ride joiners get
    /// real names, not "Rider"). Combine's multi-subscriber fan-out means this never clobbers the
    /// lobby's own subscription.
    private func bind(to session: RideRealtimeSession) {
        cancellables.removeAll()

        session.$liveState
            .compactMap { $0 }
            .sink { [weak self] update in self?.handleStateUpdate(update) }
            .store(in: &cancellables)
        // Live roster keeps rider name/avatar lookup accurate as people join/leave mid-ride.
        session.$participants
            .sink { [weak self] in self?.staticParticipants = $0 }
            .store(in: &cancellables)
        session.$onlineUserIds
            .sink { [weak self] in self?.onlineUserIds = $0 }
            .store(in: &cancellables)
        session.$connectionState
            .sink { [weak self] in self?.connectionState = $0 }
            .store(in: &cancellables)
        session.$splitActive
            .sink { [weak self] in self?.showSplitAlert = $0 }
            .store(in: &cancellables)
        // `dropFirst` skips the value `@Published` replays on subscribe, so re-entering navigation
        // (lobby → route preview → navigation) never re-fires a siren for a stale regroup/emergency.
        // Genuinely new events still arrive, and any still-open one is recovered from the authoritative
        // `openRegroup` / `openEmergency` in the ride:state_update snapshot below.
        session.$latestRegroup
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] event in self?.handleRegroupStarted(event) }
            .store(in: &cancellables)
        session.$latestRegroupResolvedId
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] id in self?.handleRegroupResolved(id) }
            .store(in: &cancellables)
        session.$latestEmergency
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] event in self?.handleEmergencyStarted(event) }
            .store(in: &cancellables)
        session.$latestEmergencyResolvedId
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] id in self?.handleEmergencyResolved(id) }
            .store(in: &cancellables)
        // Leader edited the ride mid-flight → reroute live. `dropFirst` skips the value the
        // publisher replays on subscribe, so entering navigation after an earlier edit doesn't
        // fire a spurious "rerouting" announcement.
        session.$rideUpdated
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] event in self?.handleRideUpdated(event) }
            .store(in: &cancellables)
    }

    func teardown() {
        regroupResolvedToastTask?.cancel()
        emergencySirenTimer?.invalidate()
        emergencySirenTimer = nil
        cancellables.removeAll()   // stop observing the session; the session itself keeps running
        LocationService.shared.stop()
        LocationService.shared.delegate = nil
        LocationService.shared.onHeadingUpdate = nil
    }

    func endRide() async {
        isEnding = true
        endError = nil
        do {
            try await APIClient.shared.endRide(rideId)
            showSummary = true
        } catch {
            endError = error.riderMessage
        }
        isEnding = false
    }

    /// - Parameters:
    ///   - coordinate: an explicit searched meet location; when set it wins outright.
    ///   - aheadMeters: when no explicit coordinate is given, offset the meet point this far ahead
    ///     along the route from the rider's current position (0 = right here).
    func broadcastRegroup(reason: CoordinationOverlayView.RegroupReason?, at coordinate: CLLocationCoordinate2D? = nil, aheadMeters: Double = 0) {
        guard let reason else { return }
        let target: CLLocationCoordinate2D?
        if let coordinate {
            target = coordinate
        } else if aheadMeters > 0 {
            target = coordinateAhead(meters: aheadMeters) ?? LocationService.shared.lastLocation?.coordinate
        } else {
            target = LocationService.shared.lastLocation?.coordinate
        }
        guard let target else { return }
        let lat = target.latitude
        let lng = target.longitude
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

    /// A coordinate `meters` further along the route from the rider's current position.
    ///
    /// Route choice matches what the rider is actually following:
    /// - Off-route → the **rerouted** polyline (`activeRouteCoordinates`, rebuilt from the rider's
    ///   position through the remaining stops), so the meet point lands `meters` along the reroute.
    /// - On-route → the planned `routeCoordinates`. We deliberately avoid `activeRouteCoordinates`
    ///   here because it's trimmed to a short fragment each GPS tick and, as progress nears the end,
    ///   collapses to `[projected, destination]` — which would overrun and clamp onto the destination.
    ///
    /// In both cases we project the rider onto the chosen route and walk forward, so the offset is
    /// measured from "here". Falls back to a heading offset when there's no usable route.
    private func coordinateAhead(meters: Double) -> CLLocationCoordinate2D? {
        // `navRoute` is the followed route (planned, or the reroute) and — unlike
        // `activeRouteCoordinates` — is never trimmed, so walking forward along it can't run out
        // and clamp onto the destination as progress nears the end.
        let route = navRoute.count >= 2 ? navRoute : activeRouteCoordinates
        let userLoc = LocationService.shared.lastLocation?.coordinate ?? userLocation

        guard route.count >= 2 else {
            guard let userLoc else { return nil }
            return Self.coordinate(from: userLoc, bearingDegrees: userHeading, meters: meters)
        }
        guard let userLoc else { return Self.pointAlong(route, fromProjected: route[0], segmentStart: 0, meters: meters) }

        let (segIdx, projected) = Self.nearestPointOnRoute(route, to: userLoc)
        return Self.pointAlong(route, fromProjected: projected, segmentStart: segIdx, meters: meters)
    }

    /// Nearest point on `route` to `point`, projected onto the closest segment (not just the nearest
    /// vertex). Returns the segment's start index and the projected coordinate. Uses the same
    /// flat-earth frame as `trimActiveRoute` / `distanceToLineSegment`.
    private static func nearestPointOnRoute(_ route: [CLLocationCoordinate2D], to point: CLLocationCoordinate2D) -> (segmentStart: Int, projected: CLLocationCoordinate2D) {
        var bestIdx = 0
        var bestProj = route[0]
        var bestDist = Double.infinity
        let cosLat = cos(point.latitude * .pi / 180)
        let px = point.longitude * cosLat, py = point.latitude
        for i in 0..<route.count - 1 {
            let a = route[i], b = route[i + 1]
            let ax = a.longitude * cosLat, ay = a.latitude
            let bx = b.longitude * cosLat, by = b.latitude
            let dx = bx - ax, dy = by - ay
            let lenSq = dx * dx + dy * dy
            let t = lenSq < 1e-18 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
            let proj = CLLocationCoordinate2D(
                latitude:  a.latitude  + t * (b.latitude  - a.latitude),
                longitude: a.longitude + t * (b.longitude - a.longitude)
            )
            let d = CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: CLLocation(latitude: proj.latitude, longitude: proj.longitude))
            if d < bestDist { bestDist = d; bestIdx = i; bestProj = proj }
        }
        return (bestIdx, bestProj)
    }

    /// Walks `route` forward from `projected` (a point on segment `segmentStart`), accumulating
    /// segment lengths, and returns the point `meters` further on; clamps to the route's end.
    private static func pointAlong(_ route: [CLLocationCoordinate2D], fromProjected projected: CLLocationCoordinate2D, segmentStart: Int, meters: Double) -> CLLocationCoordinate2D? {
        guard route.count >= 2 else { return nil }
        var remaining = meters
        var prev = projected
        var idx = min(segmentStart + 1, route.count - 1)
        while idx < route.count {
            let a = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let b = CLLocation(latitude: route[idx].latitude, longitude: route[idx].longitude)
            let seg = a.distance(from: b)
            if seg >= remaining {
                let frac = seg > 0 ? remaining / seg : 0
                return CLLocationCoordinate2D(
                    latitude:  prev.latitude  + (route[idx].latitude  - prev.latitude)  * frac,
                    longitude: prev.longitude + (route[idx].longitude - prev.longitude) * frac
                )
            }
            remaining -= seg
            prev = route[idx]
            idx += 1
        }
        return route.last
    }

    /// Distance still to travel along `route` from wherever the rider currently is on it.
    ///
    /// Measuring the polyline's TOTAL length only works while `trimActiveRoute` is re-cutting it to
    /// start at the rider — and that is deliberately skipped while off-route, so the bright line
    /// keeps showing the reroute being followed. The side effect was that DIST froze off-route
    /// while ETA kept counting down. Projecting the rider onto the line and summing what is left
    /// keeps the two consistent in both states, and costs one projection per fix.
    private static func remainingRouteLength(_ route: [CLLocationCoordinate2D], from location: CLLocation) -> Double {
        guard route.count >= 2 else { return 0 }
        let (segIdx, projected) = nearestPointOnRoute(route, to: location.coordinate)
        var remaining = [projected]
        let next = segIdx + 1
        if next < route.count { remaining.append(contentsOf: route[next...]) }
        return routeLengthMeters(remaining)
    }

    /// Total great-circle length of a polyline, in meters. Used to derive the local rider's
    /// remaining distance-to-goal from `activeRouteCoordinates` (which is trimmed to start at the
    /// rider's position each GPS tick) — a client-side truth that stays valid when the server's
    /// nearest-point `progress` projection is unreliable (rider off-route / simulator default fix).
    private static func routeLengthMeters(_ route: [CLLocationCoordinate2D]) -> Double {
        guard route.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 0..<route.count - 1 {
            let a = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            let b = CLLocation(latitude: route[i + 1].latitude, longitude: route[i + 1].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    /// Great-circle point `meters` from `origin` along `bearingDegrees`. Used only when no route
    /// geometry is available so a distance-ahead regroup still lands ahead of the rider.
    private static func coordinate(from origin: CLLocationCoordinate2D, bearingDegrees: Double, meters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angular = meters / earthRadius
        let bearing = (bearingDegrees.isFinite ? bearingDegrees : 0) * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    func markArrivedAtRegroup() {
        guard let regroup = activeRegroup else { return }
        SocketClient.shared.emitRegroupArrived(rideId: rideId, regroupId: regroup.regroupId)
        hasMarkedArrived = true
    }

    private func handleRegroupStarted(_ event: RegroupEvent) {
        activeRegroup = event
        hasMarkedArrived = false
        // Alert riders who didn't broadcast it — toast + a bold two-tone siren that's clearly
        // distinct from the emergency wail. The initiator already knows, so stays silent.
        if event.createdBy != myUserId {
            showRegroupToast = true
            SirenPlayer.shared.play(.regroup)
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

    /// The leader edited the ride while it's live (destination / stops / route changed). Re-seed the
    /// waypoint geometry and recompute the route so the map + turn steps follow the new plan, and
    /// alert riders with a chime + spoken "rerouting" cue. The backend has already swapped the
    /// authoritative route geometry, so progress/leaderboard re-sync on the next state update.
    private func handleRideUpdated(_ event: RideUpdatedEvent) {
        totalDistanceMeters = event.distanceMeters

        let sorted = event.waypoints.sorted { $0.order < $1.order }
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

        // Attention siren, then a spoken cue once the siren has cleared the audio session.
        SirenPlayer.shared.play(.regroup)
        VoiceAnnouncer.shared.announce("Ride updated, rerouting", after: 1.8)

        Task { await calculateRoute(from: event.waypoints, polyline: event.routePolyline) }
    }

    private func handleEmergencyStarted(_ event: EmergencyEvent) {
        // Ignore a re-broadcast of the emergency we're already showing (e.g. a late-join snapshot
        // arriving after the live event) so we don't restart the siren cadence.
        guard activeEmergency?.emergencyId != event.emergencyId else { return }
        activeEmergency = event
        startEmergencySiren()
    }

    /// Emergency siren repeats every 10s until the emergency is resolved — an unresolved emergency
    /// is meant to keep nagging the whole group, not chime once.
    private func startEmergencySiren() {
        emergencySirenTimer?.invalidate()
        SirenPlayer.shared.play(.emergency)
        emergencySirenTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            SirenPlayer.shared.play(.emergency)
        }
    }

    private func stopEmergencySiren() {
        emergencySirenTimer?.invalidate()
        emergencySirenTimer = nil
    }

    private func handleEmergencyResolved(_ emergencyId: String) {
        guard activeEmergency?.emergencyId == emergencyId else { return }
        stopEmergencySiren()
        withAnimation { activeEmergency = nil }
    }

    /// Creator- or leader-initiated clear. The local state clears when the server echoes
    /// `ride:emergency_resolved`, keeping every device in sync; we stop our own siren optimistically.
    func dismissEmergency() {
        guard let e = activeEmergency, canDismissEmergency else { return }
        stopEmergencySiren()
        SocketClient.shared.emitEmergencyDismiss(rideId: rideId, emergencyId: e.emergencyId)
    }

    // MARK: - LocationServiceDelegate

    func locationService(_ service: LocationService, didUpdate location: CLLocation, battery: Double, signalStrength: String) {
        mySpeedKmh = max(0, location.speed * 3.6)
        userLocation = location.coordinate
        if location.course >= 0 { userHeading = location.course }
        // Order matters: checkOffRoute advances `navSegmentIndex`, which is what
        // updateCurrentStep measures progress from. Reversed, every step decision used the
        // previous fix's progress.
        checkOffRoute(location: location)
        updateCurrentStep(location: location)
        refreshEtaIfNeeded(from: location)

        if needsInitialRouteCheck && !navRoute.isEmpty {
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

        // Drive DIST/ETA from the locally-trimmed remaining route rather than the server's
        // `progress`. The server value is a nearest-point projection that reads ~full (zeroing
        // distance-to-goal) whenever the rider isn't cleanly on-route — e.g. the simulator's fixed
        // default location. `activeRouteCoordinates` starts at the rider's projected position and
        // is frozen while off-route, so its length is a stable remaining-distance signal.
        if activeRouteCoordinates.count >= 2 {
            myDistanceToGoalKm = Self.remainingRouteLength(activeRouteCoordinates, from: location) / 1000
        }

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
        // Only overwrite the pre-populated leaderboard when the server actually has data.
        // The initial ride:state_update emitted on start has leaderboard: [] before any
        // location updates have been processed — don't let that clear what we pre-seeded.
        if !update.leaderboard.isEmpty {
            var rows = update.leaderboard.map { entry -> NavLeaderboardRow in
                let participant = staticParticipants.first { $0.userId == entry.userId }
                let distKm = max(0, (totalDistanceMeters - entry.progress) / 1000)
                return NavLeaderboardRow(
                    id: entry.userId, rank: entry.rank, name: entry.name,
                    avatarUrl: participant?.avatarUrl,
                    distanceToGoalKm: distKm,
                    isMe: entry.userId == myUserId
                )
            }

            // The server leaderboard only carries riders who've posted a location tick, so
            // joined-but-offline riders (never broadcast, or dropped) would vanish. Keep every
            // joined participant present as a trailing row; the view renders it disabled via
            // `onlineUserIds`, matching how a rider who drops mid-navigation stays visible.
            let ranked = Set(rows.map(\.id))
            var nextRank = (rows.map(\.rank).max() ?? 0) + 1
            for p in staticParticipants where p.status != "LEFT" && !ranked.contains(p.userId) {
                rows.append(NavLeaderboardRow(
                    id: p.userId, rank: nextRank, name: p.name,
                    avatarUrl: p.avatarUrl,
                    distanceToGoalKm: totalDistanceMeters / 1000,
                    isMe: p.userId == myUserId
                ))
                nextRank += 1
            }

            leaderboardRows = rows
        }

        // Riders with a live position this tick — and cache each position so a rider who later
        // goes offline can stay pinned at their final spot instead of disappearing.
        var live: [LiveRider] = update.participants.compactMap { p in
            guard let lat = p.lat, let lng = p.lng else { return nil }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            lastKnownRiderPositions[p.userId] = coord
            let participant = staticParticipants.first { $0.userId == p.userId }
            let lbEntry = update.leaderboard.first { $0.userId == p.userId }
            let distKm = max(0, (totalDistanceMeters - p.progress) / 1000)
            return LiveRider(
                id: p.userId,
                name: participant?.name ?? lbEntry?.name ?? "Rider",
                avatarUrl: participant?.avatarUrl,
                rank: lbEntry?.rank ?? 99,
                distanceToGoalKm: distKm,
                speedKmh: (p.speed ?? 0) * 3.6,
                coordinate: coord,
                isMe: p.userId == myUserId
            )
        }

        // Retain any joined rider who has no position this tick at their last-known spot. The pin
        // renders dimmed via `onlineUserIds` (same rule as the leaderboard row), so an offline rider
        // remains visible where they dropped instead of vanishing from the map.
        let present = Set(live.map(\.id))
        for p in staticParticipants where p.status != "LEFT" && p.userId != myUserId && !present.contains(p.userId) {
            guard let coord = lastKnownRiderPositions[p.userId] else { continue }
            let lbEntry = leaderboardRows.first { $0.id == p.userId }
            live.append(LiveRider(
                id: p.userId,
                name: p.name,
                avatarUrl: p.avatarUrl,
                rank: lbEntry?.rank ?? 99,
                distanceToGoalKm: lbEntry?.distanceToGoalKm ?? (totalDistanceMeters / 1000),
                speedKmh: 0,
                coordinate: coord,
                isMe: false
            ))
        }
        riders = live

        if let myEntry = update.leaderboard.first(where: { $0.userId == myUserId }) {
            myRank = myEntry.rank
            // Until the first local GPS fix arrives, fall back to the server's route progress.
            // Once GPS is driving, `myDistanceToGoalKm` is owned by the local route-trim path
            // (see `locationService(_:didUpdate:…)`), which is robust to off-route projection.
            if userLocation == nil {
                myDistanceToGoalKm = max(0, (totalDistanceMeters - myEntry.progress) / 1000)
            }
        }

        if update.status == "COMPLETED" { showSummary = true }

        // Late-join: pick up any open regroup / emergency from the authoritative state snapshot.
        if activeRegroup == nil, let incoming = update.openRegroup {
            handleRegroupStarted(incoming)
        }
        if activeEmergency == nil, let incoming = update.openEmergency {
            handleEmergencyStarted(incoming)
        }
    }

    private func calculateRoute(from waypoints: [Waypoint], polyline: String? = nil) async {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }

        var allCoords: [CLLocationCoordinate2D] = []
        var totalTime: TimeInterval = 0
        var steps: [NavStep] = []
        // One entry per leg (start→stop₀, stop₀→stop₁, …): running travel time on arrival at each stop.
        // Appended every iteration — even when a leg fails to route — so the index stays aligned with
        // `remainingStops`.
        var cumulativeStopTimes: [TimeInterval] = []

        for i in 0..<sorted.count - 1 {
            let origin = CLLocationCoordinate2D(latitude: sorted[i].lat,   longitude: sorted[i].lng)
            let dest   = CLLocationCoordinate2D(latitude: sorted[i+1].lat, longitude: sorted[i+1].lng)
            if let result = try? await GoogleDirectionsService.route(from: origin, to: dest) {
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
                totalTime += result.durationSeconds
                // Every step is kept, including any without instruction text: they still occupy
                // real distance, and dropping them used to break the chain of along-route
                // positions. Display falls forward to the next step that has text.
                for step in result.steps {
                    steps.append(NavStep(
                        instruction: step.instruction,
                        maneuver: step.maneuver,
                        endCoordinate: step.endCoordinate,
                        distanceMeters: step.distanceMeters,
                        endDistanceAlongRoute: 0   // stamped below, once the geometry is known
                    ))
                }
            }
            cumulativeStopTimes.append(totalTime)
        }

        // Draw and track the leader-selected route geometry when available; the steps
        // above (turn instructions) come from the live recompute either way.
        let geometry = GoogleDirectionsService.decodedRoute(polyline) ?? allCoords

        // Step ends are projected onto the geometry we actually follow rather than assumed to lie
        // on it: they come from the legs just recomputed, while `geometry` may be the leader's
        // stored polyline, and the two need not share vertices.
        adoptNavRoute(geometry, steps: steps)

        // `adoptNavRoute` above already set navRoute / its prefix distances / navSegmentIndex.
        routeCoordinates         = geometry
        activeRouteCoordinates   = geometry   // full route until first GPS update trims it
        routeExpectedTravelTime  = totalTime
        stopCumulativeDurations  = cumulativeStopTimes
        totalStopCount           = cumulativeStopTimes.count
        consecutiveOffCount      = 0
        consecutiveOnCount       = 0
        needsInitialRouteCheck   = true
        routeVersion += 1
    }

    /// Which maneuver comes next, derived from how far along the route the rider actually is —
    /// the model Google Maps uses.
    ///
    /// This replaced a proximity trigger that advanced only when a GPS fix landed within 30 m
    /// (straight-line) of the step's end coordinate. Miss that window once — GPS scatter, a fix
    /// interval that straddles the junction at speed, a step end snapped to the far side of a
    /// divided road — and the distance only grows as the rider drives away, so the step could
    /// never advance again: the very first instruction ("Head west on …") stuck for the whole
    /// ride, which is exactly the reported symptom. It also advanced at most one step per fix, so
    /// a cluster of short steps (roundabout exits, quick doubles) left it permanently behind.
    ///
    /// Comparing progress against each step's along-route end is a pure function of position, so
    /// it self-corrects: passing a turn advances by itself, and several steps can be crossed in
    /// one fix.
    private func updateCurrentStep(location: CLLocation) {
        guard !navSteps.isEmpty else { return }
        let progress = progressAlongRoute(location)

        // First step that still ends ahead of us. The 5 m slack avoids sitting exactly on a
        // boundary and flickering between two steps while stationary.
        let computed = navSteps.firstIndex { $0.endDistanceAlongRoute > progress + 5 }
            ?? navSteps.count - 1
        // Forward-only, mirroring the route progress index it is derived from.
        currentStepIndex = max(currentStepIndex, computed)

        let step = navSteps[currentStepIndex]
        // Along-route rather than straight-line: "300 m" should mean 300 m of driving, which is
        // what Google shows and what actually matters around a curve.
        distanceToNextTurnMeters = max(0, step.endDistanceAlongRoute - progress)
        currentInstruction = displayedInstruction(from: currentStepIndex)
        currentManeuver    = displayedManeuver(from: currentStepIndex)
    }

    /// Rider's distance along the drawn route. Built on `navSegmentIndex`, which
    /// `advanceRouteProgress` only ever moves forward inside a window — so progress cannot jump
    /// backwards (or leap ahead) where a route passes close to itself.
    private func progressAlongRoute(_ location: CLLocation) -> Double {
        guard navRoute.count >= 2,
              navRouteCumulative.count == navRoute.count else { return 0 }
        let i = min(navSegmentIndex, navRoute.count - 2)
        let a = navRoute[i]
        let projected = Self.projectOntoSegment(location.coordinate, a: a, b: navRoute[i + 1])
        let alongSegment = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: projected.latitude, longitude: projected.longitude))
        return navRouteCumulative[i] + alongSegment
    }

    /// Steps without instruction text still count toward distance, so for display we fall forward
    /// to the next step that has text.
    private func displayedInstruction(from index: Int) -> String {
        guard index < navSteps.count else { return "" }
        for step in navSteps[index...] where !step.instruction.isEmpty { return step.instruction }
        return ""
    }

    private func displayedManeuver(from index: Int) -> String {
        guard index < navSteps.count else { return "" }
        for step in navSteps[index...] where !step.instruction.isEmpty { return step.maneuver ?? "" }
        return ""
    }

    /// Prefix distances: `result[i]` is metres from the route start to vertex `i`.
    private static func cumulativeDistances(_ route: [CLLocationCoordinate2D]) -> [Double] {
        guard !route.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: route.count)
        for i in 1..<route.count {
            let a = CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
            let b = CLLocation(latitude: route[i].latitude,     longitude: route[i].longitude)
            result[i] = result[i - 1] + a.distance(from: b)
        }
        return result
    }

    /// Stamps each step with where its end falls along `route`, by projecting the end coordinate
    /// onto the polyline. Clamped to be non-decreasing: a projection that landed behind its
    /// predecessor (a route that doubles back near itself) would make that step unreachable and
    /// strand the banner, which is the failure mode this whole path exists to avoid.
    private static func stampAlongRouteDistances(
        _ steps: [NavStep],
        route: [CLLocationCoordinate2D],
        cumulative: [Double]
    ) -> [NavStep] {
        guard route.count >= 2, cumulative.count == route.count else { return steps }
        let total = cumulative[cumulative.count - 1]
        var stamped: [NavStep] = []
        var previous: Double = 0
        for var step in steps {
            let (segIdx, projected) = nearestPointOnRoute(route, to: step.endCoordinate)
            let a = CLLocation(latitude: route[segIdx].latitude, longitude: route[segIdx].longitude)
            let along = cumulative[segIdx] + a.distance(
                from: CLLocation(latitude: projected.latitude, longitude: projected.longitude)
            )
            step.endDistanceAlongRoute = min(max(along, previous), total)
            previous = step.endDistanceAlongRoute
            stamped.append(step)
        }
        // The last step ends at the destination by definition; snapping it there stops a slightly
        // short projection from leaving the final instruction unreachable.
        if !stamped.isEmpty {
            stamped[stamped.count - 1].endDistanceAlongRoute = total
        }
        return stamped
    }

    /// Closest point to `point` on the segment a→b. Shared by progress tracking and
    /// `trimActiveRoute`, which previously inlined the same flat-earth projection.
    private static func projectOntoSegment(
        _ point: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let cosLat = cos(a.latitude * .pi / 180)
        let ax = a.longitude * cosLat, ay = a.latitude
        let bx = b.longitude * cosLat, by = b.latitude
        let px = point.longitude * cosLat, py = point.latitude
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        guard lenSq >= 1e-18 else { return a }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        return CLLocationCoordinate2D(
            latitude:  a.latitude  + t * (b.latitude  - a.latitude),
            longitude: a.longitude + t * (b.longitude - a.longitude)
        )
    }

    /// Keeps `etaSecondsRemaining` moving on every fix, and re-asks the Routes API for a
    /// traffic-aware figure once per `etaRefreshInterval`.
    ///
    /// The countdown between refreshes is what makes it feel live: subtracting elapsed wall time
    /// from the last known figure is self-correcting — if the rider is stopped, the number keeps
    /// falling until the next refresh puts it back up, which is the honest reflection of losing
    /// time in traffic. The old estimate scaled the PLANNED duration by remaining distance, so
    /// standing still changed nothing at all.
    private func refreshEtaIfNeeded(from location: CLLocation) {
        if let base = etaBaseSeconds {
            etaSecondsRemaining = max(0, base - Date().timeIntervalSince(etaBaseDate))
        }

        guard !isEtaRefreshInFlight,
              Date().timeIntervalSince(lastEtaRefresh) >= Self.etaRefreshInterval,
              // Same target as the planned estimate: the next stop on a multi-stop ride,
              // otherwise the destination.
              let target = remainingStops.first ?? destinationCoordinate
        else { return }

        lastEtaRefresh = Date()
        isEtaRefreshInFlight = true
        let origin = location.coordinate
        Task { [weak self] in
            let result = try? await GoogleDirectionsService.route(
                from: origin, to: target, trafficAware: true
            )
            guard let self else { return }
            self.isEtaRefreshInFlight = false
            guard let seconds = result?.durationSeconds, seconds > 0 else { return }
            self.etaBaseSeconds      = seconds
            self.etaBaseDate         = Date()
            self.etaSecondsRemaining = seconds
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
        // The reroute's own turn instructions. Previously discarded, which left the banner reciting
        // maneuvers from a route the rider had already left — "turn left" at a junction that is no
        // longer on the path.
        var steps: [NavStep] = []
        for i in 0..<stops.count - 1 {
            guard let result = try? await GoogleDirectionsService.route(
                from: stops[i], to: stops[i + 1], trafficAware: false
            ) else { continue }
            coords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
            for step in result.steps {
                steps.append(NavStep(
                    instruction: step.instruction,
                    maneuver: step.maneuver,
                    endCoordinate: step.endCoordinate,
                    distanceMeters: step.distanceMeters,
                    endDistanceAlongRoute: 0
                ))
            }
        }
        isRerouteInFlight = false
        guard !coords.isEmpty else { return }

        activeRouteCoordinates = coords
        // Navigation switches wholesale onto the reroute: progress, off-route checks, trimming and
        // steps all now refer to it. Without this the rider stays "off" the abandoned plan forever
        // and re-reroutes every 200 m, which would also reset the steps every 200 m.
        adoptNavRoute(coords, steps: steps)
    }

    /// Adopts `route` as the polyline being followed: rebuilds its prefix distances, restamps the
    /// steps onto it, and rewinds progress to its start. Used for the initial route and for every
    /// reroute, so both paths can't drift apart.
    private func adoptNavRoute(_ route: [CLLocationCoordinate2D], steps: [NavStep]) {
        // The old ETA described a route we're no longer on; drop it and let the next fix refresh.
        etaBaseSeconds      = nil
        etaSecondsRemaining = nil
        lastEtaRefresh      = .distantPast
        navRoute            = route
        navRouteCumulative  = Self.cumulativeDistances(route)
        navSegmentIndex     = 0
        navSteps            = Self.stampAlongRouteDistances(steps, route: route, cumulative: navRouteCumulative)
        currentStepIndex    = 0
        currentInstruction       = displayedInstruction(from: 0)
        currentManeuver          = displayedManeuver(from: 0)
        distanceToNextTurnMeters = navSteps.first?.endDistanceAlongRoute ?? 0
    }

    /// Advance `navSegmentIndex` to the closest upcoming segment, never backwards.
    private func advanceRouteProgress(to location: CLLocation) {
        guard navRoute.count >= 2 else { return }
        let lookEnd = min(navRoute.count - 2, navSegmentIndex + 200)
        guard lookEnd >= navSegmentIndex else { return }

        var minDist = Double.infinity
        var bestIdx = navSegmentIndex
        for i in navSegmentIndex...lookEnd {
            let d = distanceToLineSegment(from: location, a: navRoute[i], b: navRoute[i + 1])
            if d < minDist { minDist = d; bestIdx = i }
            if minDist < 5 { break }
        }
        // Only advance if user is actually near the route — prevents a far-away GPS fix
        // from jumping the index to the end of a short route, which caused the straight-line bug.
        if bestIdx > navSegmentIndex && minDist <= 80 {
            navSegmentIndex = bestIdx
        }
    }

    /// Projects the user onto the current segment and rebuilds activeRouteCoordinates
    /// so the bright polyline starts exactly at the user's position.
    /// Only called when on-route; off-route uses calculateFullReroute instead.
    private func trimActiveRoute(to location: CLLocation) {
        guard navRoute.count >= 2 else { return }
        let i    = navSegmentIndex
        let next = min(i + 1, navRoute.count - 1)
        let a    = navRoute[i]
        let b    = navRoute[next]

        let projected = Self.projectOntoSegment(location.coordinate, a: a, b: b)

        var trimmed: [CLLocationCoordinate2D] = [projected]
        if next < navRoute.count {
            trimmed.append(contentsOf: navRoute[next...])
        }
        activeRouteCoordinates = trimmed
    }

    /// Minimum perpendicular distance to any segment in a window around the current progress index.
    private func minimumDistanceToUpcomingRoute(from location: CLLocation) -> Double {
        guard navRoute.count >= 2 else { return 0 }
        let start = max(0, navSegmentIndex - 5)
        let end = min(navRoute.count - 2, navSegmentIndex + 100)
        guard end >= start else { return 0 }

        var minDist = Double.infinity
        for i in start...end {
            let d = distanceToLineSegment(from: location, a: navRoute[i], b: navRoute[i + 1])
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
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @StateObject private var vm = NavigationViewModel()

    @Environment(\.verticalSizeClass) private var vSizeClass

    @State private var cameraCommand: MapCameraCommand? = nil
    @State private var selectedRiderId: String? = nil
    @State private var showRegroup = false
    @State private var isBroadcasting = false
    @State private var showEndError = false
    @State private var showEndConfirm = false
    @State private var isFreeLooking: Bool = false
    @State private var lastInteractionDate: Date = .distantPast
    @State private var isNavigationActive: Bool = false
    // Last position/heading the follow camera actually moved to. Used to skip
    // re-issuing a camera command when the rider has barely moved or turned.
    @State private var lastCameraCoord: CLLocationCoordinate2D? = nil
    @State private var lastCameraHeading: Double = 0
    // Low-passed speed driving the camera zoom. Raw `CLLocation.speed` swings several km/h
    // between fixes; fed straight into a continuous zoom curve that makes the map breathe.
    // The SPEED readout still shows the raw value.
    @State private var cameraSpeedKmh: Double = 0
    // Measured height of whichever bottom bar is showing — the live-navigation control bar
    // or the pre-navigation preview bar. Measured rather than derived from their paddings:
    // the preview bar alone stacks a divider, a two-line row and a 56pt button across five
    // padding values, and any constant reproducing that would drift the moment one changes.
    // The map reserves exactly this much so it ends at the bar's top edge either way.
    @State private var bottomBarHeight: CGFloat = 0
    // Bottom edge of the top chrome (back button row + leaderboard strip) in screen coords. The
    // map's top edge is screen y=0, so this doubles as the map-space inset that off-screen rider
    // chips must stay below. Measured rather than hardcoded so it follows the leaderboard growing
    // with the convoy, and the landscape layout, on its own.
    @State private var topChromeBottom: CGFloat = 0
    // Screen geometry for off-screen riders, produced by the map coordinator.
    @State private var edgeIndicators: [EdgeIndicator] = []

    private var isLandscape: Bool { vSizeClass == .compact }

    private var destinationName: String { appState.currentRide?.destinationName ?? "Destination" }

    var body: some View {
        coreView
            .sheet(isPresented: $showRegroup, onDismiss: { isBroadcasting = false }) {
                RegroupBottomSheet(
                    onBroadcast: { reason, aheadMeters in
                        guard !isBroadcasting else { return }
                        isBroadcasting = true
                        // No coordinate override: the meet point is always derived from the
                        // rider's own position plus the chosen distance ahead on the route.
                        vm.broadcastRegroup(reason: reason, aheadMeters: aheadMeters)
                        showRegroup = false
                    },
                    isBroadcasting: isBroadcasting
                )
            }
            .onChange(of: vm.activeRegroup) { _, regroup in handleRegroupChanged(regroup) }
            .navigationDestination(isPresented: $vm.showSummary) {
                RideSummaryView(rideId: rideId, rideTitle: appState.currentRide?.title, isPostRide: true)
            }
            .confirmationDialog(
                "End this ride for everyone?",
                isPresented: $showEndConfirm,
                titleVisibility: .visible
            ) {
                Button("End Ride", role: .destructive) { Task { await vm.endRide() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Every rider stops sharing their location and the ride summary is generated. This can't be undone.")
            }
            .alert("Couldn't End Ride", isPresented: $showEndError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.endError ?? "An error occurred.")
            }
            .onChange(of: vm.endError) { _, err in if err != nil { showEndError = true } }
            // Ride is over (ended by leader or COMPLETED broadcast) → tear down the shared session.
            .onChange(of: vm.showSummary) { _, show in if show { rideSession.stop() } }
    }

    private var coreView: some View {
        ZStack {
            mapLayer
            if isNavigationActive {
                OffscreenIndicatorsOverlay(clusters: edgeClusters, onTapRider: focusRider)
            }
            // GeometryReader only to read the HUD's real safe-area inset — it fills the
            // ZStack and the HUD's VStack fills it back, so layout is unchanged.
            GeometryReader { proxy in
                hudLayer(bottomInset: proxy.safeAreaInsets.bottom)
            }
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
        // Normally the lobby already started the session; start() is idempotent for the same ride
        // (just re-joins), so this also covers entering navigation without a live lobby VM.
        if let token = try? await Clerk.shared.auth.getToken() {
            rideSession.start(rideId: rideId, token: token, myUserId: userId,
                              seedParticipants: ride.participants, leaderId: ride.leaderId)
        }
        await vm.setup(rideId: rideId, ride: ride, myUserId: userId, session: rideSession)
    }

    // MARK: - Map

    private var navMapPins: [MapPin] {
        var pins: [MapPin] = []
        if let coord = vm.userLocation {
            pins.append(MapPin(id: "me", coordinate: coord, style: .userLocation(heading: vm.userHeading), anchorBottom: false))
        }
        for rider in vm.riders.filter({ !$0.isMe }) {
            let distText: String? = vm.userLocation.map { me in
                let meters = CLLocation(latitude: me.latitude, longitude: me.longitude)
                    .distance(from: CLLocation(latitude: rider.coordinate.latitude, longitude: rider.coordinate.longitude))
                return Self.formatDistance(meters)
            }
            pins.append(MapPin(id: rider.id, coordinate: rider.coordinate,
                               style: .rider(name: rider.name, avatarUrl: rider.avatarUrl,
                                             isMe: false, rank: rider.rank,
                                             isSelected: selectedRiderId == rider.id,
                                             isOffline: !vm.onlineUserIds.contains(rider.id)),
                               distanceText: distText))
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
        if let emergency = vm.activeEmergency {
            pins.append(MapPin(id: "emergency", coordinate: CLLocationCoordinate2D(latitude: emergency.lat, longitude: emergency.lng), style: .emergency))
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
            onInteraction: onMapInteraction,
            onEdgeIndicators: { edgeIndicators = $0 },
            topOverlayHeight: isNavigationActive ? topChromeBottom : 0
        )
        // Bleeds under the notch and side insets, but NOT the bottom — the bottom edge is
        // set by the measured bar height, so ignoring the bottom safe area would expand the
        // map back over the bar.
        .ignoresSafeArea(edges: [.top, .horizontal])
        .padding(.bottom, bottomBarHeight)
    }

    /// Off-screen riders joined with their display metadata, then clustered by
    /// screen-edge proximity for the indicator overlay.
    private var edgeClusters: [EdgeCluster] {
        let byId = Dictionary(uniqueKeysWithValues: vm.riders.map { ($0.id, $0) })
        let models: [EdgeChipModel] = edgeIndicators.compactMap { ind in
            guard let rider = byId[ind.id] else { return nil }
            return EdgeChipModel(
                id: ind.id, name: rider.name, avatarUrl: rider.avatarUrl,
                isOffline: !vm.onlineUserIds.contains(ind.id),
                edgePoint: ind.edgePoint, arrowAngle: ind.arrowAngle,
                distanceMeters: ind.distanceMeters
            )
        }
        return clusterIndicators(models)
    }

    /// Compact distance label for rider markers. Quantized (10 m under 1 km, 0.1 km
    /// above) so the marker only re-bakes when the shown value actually changes.
    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", meters / 1000)
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

    /// How early (in meters) to begin pulling the camera back before a turn.
    /// Scales with speed so fast riders see the maneuver framed sooner.
    private var maneuverApproachMeters: Double {
        max(140, cameraSpeedKmh / 3.6 * 7)   // ~7s of travel, floor 140 m
    }
    /// Zoom levels to pull back when approaching a maneuver. Half a level at the Google-matched
    /// base zoom; a full level reads as the map lurching.
    private let maneuverZoomOut: Float = 0.5

    private var navZoom: Float {
        // Speed → zoom lives in MapCameraCommand so the map layer holds one definition of how
        // close the guidance camera sits. Tilt and viewport centering are NOT part of it.
        let base = MapCameraCommand.navZoom(forSpeedKmh: cameraSpeedKmh)
        // Approaching a turn → pull back to reveal the upcoming road; once past
        // the maneuver `hasUpcomingTurn`/distance reset and we return to `base`.
        // The camera's animate(to:) smooths the zoom transition both ways.
        if vm.hasUpcomingTurn, vm.distanceToNextTurnMeters <= maneuverApproachMeters {
            return base - maneuverZoomOut
        }
        return base
    }

    /// Flat, top-down, heading-up — no 3D pitch. Lives in MapCameraCommand so the map layer and
    /// this screen can't disagree about what the guidance camera looks like.
    private var navTilt: Double { MapCameraCommand.navTilt }

    private func resumeNavigation() {
        isFreeLooking = false
        lastInteractionDate = .distantPast
        guard let coord = vm.userLocation else { return }
        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: true, framing: .roadAhead)
        )
    }

    private func beginNavigation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isNavigationActive = true }
        guard let coord = vm.userLocation else { return }
        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: true, framing: .roadAhead)
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
        // Track speed on every tick — including the ones that don't move the camera — so the
        // zoom is already correct whenever a camera command does go out.
        cameraSpeedKmh = wasZero ? vm.mySpeedKmh : cameraSpeedKmh + 0.25 * (vm.mySpeedKmh - cameraSpeedKmh)
        let isMoving    = vm.mySpeedKmh > 2.0
        let idleSeconds = Date().timeIntervalSince(lastInteractionDate)
        let shouldFollow = wasZero || (isMoving && idleSeconds >= 3.0)
        if isFreeLooking && shouldFollow { isFreeLooking = false }
        guard shouldFollow else { return }

        // Only move the camera when the rider has moved or turned enough to
        // justify it — avoids re-animating on every GPS tick from jittery
        // stationary fixes. The first fix (wasZero) always snaps into place.
        if !wasZero, let last = lastCameraCoord {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            let rawDelta   = abs(vm.userHeading - lastCameraHeading).truncatingRemainder(dividingBy: 360)
            let headingChange = min(rawDelta, 360 - rawDelta)
            if moved < 5 && headingChange < 3 { return }
        }
        lastCameraCoord   = coord
        lastCameraHeading = vm.userHeading

        cameraCommand = MapCameraCommand(
            id: UUID(),
            action: .navigate(lat: coord.latitude, lng: coord.longitude,
                              zoom: navZoom, bearing: vm.userHeading, tilt: navTilt, animated: !wasZero, framing: .roadAhead)
        )
    }

    /// Tapping an edge indicator flies the camera to that rider and breaks
    /// follow; the RESUME capsule (shown while `isFreeLooking`) re-engages nav.
    private func focusRider(_ id: String) {
        guard let rider = vm.riders.first(where: { $0.id == id }) else { return }
        isFreeLooking = true
        lastInteractionDate = Date()
        selectedRiderId = id
        cameraCommand = MapCameraCommand.focus(
            lat: rider.coordinate.latitude, lng: rider.coordinate.longitude, zoom: 16
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

    private func hudLayer(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY.rounded(.up)
                } action: { bottom in
                    topChromeBottom = bottom
                }

            if vm.connectionState == .reconnecting {
                ConnectionBanner(state: vm.connectionState)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: vm.connectionState)
            }

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

                if let emergency = vm.activeEmergency {
                    EmergencyAlertBanner(
                        reporterName: vm.emergencyReporterName,
                        message: emergency.message,
                        // Only the raiser or the leader can clear it; for everyone else the banner
                        // has no dismiss control and persists (with the pin) until they do.
                        onDismiss: vm.canDismissEmergency ? { vm.dismissEmergency() } : nil
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: vm.activeEmergency)
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
                Group {
                    if vm.hasMarkedArrived {
                        waitingForOthersPill
                    } else {
                        arrivedButton
                    }
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: vm.hasMarkedArrived)
                .animation(.spring(), value: vm.activeRegroup != nil)
            }

            Group {
                if isNavigationActive {
                    bottomControls(bottomInset: bottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    navigationPreviewBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Feeds the live height to `bottomBarHeight` so the map's reserve follows the
            // real bar — including the swap between the two bars. `onGeometryChange` is the
            // supported way to do this; writing state from a GeometryReader's body would
            // mutate it mid-layout. Rounded up so sub-point jitter can't churn the map frame.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded(.up)
            } action: { height in
                bottomBarHeight = height
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
                    turnInstructionCard(expand: !isLandscape)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    if isLandscape {
                        landscapeLeaderboardStrip
                            .transition(.opacity)
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
                        Text(vm.liveRiderCount > 0 ? "\(vm.liveRiderCount)" : "--")
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
            .padding(.horizontal, 20)   // matches the banners below and the bottom bar
            .animation(.easeInOut(duration: 0.35), value: isNavigationActive)

            if isNavigationActive && !isLandscape {
                leaderboardStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.35), value: isNavigationActive)
    }

    private func turnInstructionCard(expand: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primaryFixed)
                    .frame(width: 36, height: 36)
                Image(systemName: vm.currentInstruction.isEmpty
                      ? "arrow.up"
                      : maneuverIcon(for: vm.currentManeuver, instruction: vm.currentInstruction))
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
        .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primaryFixed.opacity(0.3), lineWidth: 1))
    }

    /// Arrow for the current maneuver, from the Routes API's `maneuver` enum. Locale-independent
    /// and unambiguous, unlike scanning the instruction text — which matched road names
    /// ("Turn right onto Left Cross Rd" hit "left" first, drawing the wrong arrow) and flattened
    /// slight/sharp/ramp variants into one. The text scan survives only as a fallback for a step
    /// that arrives without a maneuver.
    private func maneuverIcon(for maneuver: String, instruction: String) -> String {
        switch maneuver {
        case "TURN_LEFT", "TURN_SHARP_LEFT":   return "arrow.turn.up.left"
        case "TURN_RIGHT", "TURN_SHARP_RIGHT": return "arrow.turn.up.right"
        case "TURN_SLIGHT_LEFT", "RAMP_LEFT":  return "arrow.up.left"
        case "TURN_SLIGHT_RIGHT", "RAMP_RIGHT": return "arrow.up.right"
        case "UTURN_LEFT":                     return "arrow.uturn.left"
        case "UTURN_RIGHT":                    return "arrow.uturn.right"
        case "MERGE":                          return "arrow.merge"
        case "FORK_LEFT", "FORK_RIGHT":        return "arrow.triangle.branch"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT":
            return "arrow.triangle.turn.up.right.circle"
        case "FERRY", "FERRY_TRAIN":           return "ferry"
        case "DEPART", "STRAIGHT", "NAME_CHANGE": return "arrow.up"
        default:
            return legacyManeuverIcon(for: instruction)
        }
    }

    /// Text-derived arrow. Only reached when a step carries no `maneuver`.
    private func legacyManeuverIcon(for instruction: String) -> String {
        let l = instruction.lowercased()
        if l.contains("arrive") || l.contains("destination") { return "flag.checkered" }
        if l.contains("u-turn") || l.contains("uturn") { return "arrow.uturn.left" }
        if l.contains("roundabout") || l.contains("rotary") { return "arrow.triangle.turn.up.right.circle" }
        if l.contains("merge") { return "arrow.merge" }
        if l.contains("left") { return "arrow.turn.up.left" }
        if l.contains("right") { return "arrow.turn.up.right" }
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
                            LiveLeaderboardCard(row: row, isSelected: selectedRiderId == row.id,
                                                isOffline: !row.isMe && !vm.onlineUserIds.contains(row.id))
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
                            LiveLeaderboardCard(row: row, isSelected: selectedRiderId == row.id,
                                                isOffline: !row.isMe && !vm.onlineUserIds.contains(row.id))
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

    /// Adaptive by construction rather than by tuned constants: `ViewThatFits`
    /// measures each variant against the width SwiftUI actually proposes — any
    /// device, orientation, split-screen or Dynamic Type setting — and picks the
    /// first that fits. Roomiest first, so a wide screen keeps full spacing and a
    /// narrow one degrades by shedding spacing, then unit labels, in that order.
    /// `barStat`'s `minimumScaleFactor` remains only as the last-resort net for
    /// widths narrower than even the tightest variant.
    /// `bottomInset` is the real bottom safe-area inset, read from inside the HUD. The
    /// map's `.ignoresSafeArea()` consumes the safe area for its ZStack siblings, so the
    /// HUD spans to the screen edge and this inset is the FULL clearance the content needs
    /// to stay off the home indicator — not an addition to some inset already applied.
    /// Reading it (rather than hardcoding 34) is what makes it right on home-button
    /// devices, where it's 0 and only `barMinBottomPad` applies.
    private func bottomControls(bottomInset: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            controlRow(spacing: 16, showUnits: true)
            controlRow(spacing: 10, showUnits: true)
            controlRow(spacing: 8,  showUnits: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, barTopPad)
        // Content sits above the home indicator; the material behind it still runs to the
        // screen edge, so no map shows through below the bar. `max` keeps a sane gap on
        // home-button devices where the inset is 0.
        .padding(.bottom, max(barMinBottomPad, bottomInset - barBottomTrim))
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.surfaceDim.opacity(0.55)
            }
            // Covers the bottom edge even if a future layout hands the HUD an inset frame.
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.outlineVariant.opacity(0.25))
                .frame(height: 1)
        }
    }

    private var barTopPad: CGFloat       { isLandscape ? 8 : 10 }
    private var barMinBottomPad: CGFloat { isLandscape ? 8 : 10 }
    /// How much of the home-indicator inset to claim back. The full inset keeps controls clear of
    /// the indicator, but the last third of it reads as dead space under the bar. Giving 10pt back
    /// still leaves the buttons ~24pt above the screen edge, clear of the home-gesture strip.
    private var barBottomTrim: CGFloat   { isLandscape ? 0 : 10 }

    /// One candidate layout for the bottom bar. `Spacer(minLength:)` keeps the
    /// ideal width measurable so `ViewThatFits` can compare candidates.
    private func controlRow(spacing: CGFloat, showUnits: Bool) -> some View {
        HStack(spacing: spacing) {
            barStat(
                label: "SPEED",
                value: vm.mySpeedKmh > 0 ? String(format: "%.0f", vm.mySpeedKmh) : "--",
                unit: showUnits ? "KM/H" : nil
            )
            barDivider
            barStat(label: "ETA", value: vm.etaString, unit: nil)
            barDivider
            barStat(
                label: "DIST",
                value: vm.myDistanceToGoalKm > 0 ? String(format: "%.1f", vm.myDistanceToGoalKm) : "--",
                unit: showUnits ? "KM" : nil
            )
            Spacer(minLength: 6)
            regroupButton
            endRideButton
        }
    }

    /// 48pt portrait — comfortably above the 44pt minimum touch target, and it stops
    /// the buttons from setting a row height 21pt taller than the stats beside them.
    private var buttonSize: CGFloat { isLandscape ? 44 : 48 }

    // A single stat written directly on the bar — no card/pill. `lineLimit(1)` keeps multi-digit
    // values (e.g. 3-digit speed) on one line; `minimumScaleFactor` lets them give up a little
    // size when the row is full rather than forcing the HStack wider than the screen. Do NOT use
    // `fixedSize` here: three stats plus both buttons need ~438pt at worst-case values, so on a
    // 393pt screen a fixed-width row bleeds past both edges and clips the outermost glyphs.
    private func barStat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.statLabel)
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(isLandscape ? .statValueCompact : .statValue)
                    .foregroundColor(Color.onSurface)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.statUnit)
                        .foregroundColor(Color.onSurfaceVariant)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color.outlineVariant.opacity(0.25))
            .frame(width: 1, height: isLandscape ? 26 : 30)
    }

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
                // Ending is irreversible and ends it for every rider in the convoy, so the leader
                // confirms first. A mis-tap here used to end the ride outright — and this button
                // sits next to regroup, on a phone being tapped at a set of lights.
                showEndConfirm = true
            } else {
                // Not the leader: this only backs out of the navigation screen, nothing to confirm.
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
        Button(action: { vm.markArrivedAtRegroup() }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("MARK AS ARRIVED")
                    .font(.labelCaps)
                    .tracking(0.5)
            }
            .foregroundColor(Color.onPrimaryFixed)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Color.primaryFixed, in: Capsule())
            .shadow(color: Color.primaryFixed.opacity(0.5), radius: 12, y: 2)
        }
    }

    // Subtle, out-of-focus indicator shown after this rider has marked arrived,
    // while we wait for the regroup to be resolved. Deliberately small so it
    // doesn't compete with the map or the primary bottom controls.
    private var waitingForOthersPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("WAITING FOR OTHERS")
                .font(.labelCaps)
                .tracking(0.5)
        }
        .foregroundColor(Color.onSurfaceVariant)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
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
    var isOffline: Bool = false

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
            .overlay(alignment: .bottomTrailing) {
                // Grey dot = this rider's heartbeats lapsed (backgrounded / lost connection).
                if isOffline {
                    Circle().fill(Color.onSurfaceVariant)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.surfaceContainerHigh, lineWidth: 1.5))
                }
            }

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
        .opacity(isOffline ? 0.5 : 1)
        .animation(.spring(response: 0.3), value: isSelected)
        .animation(.easeInOut(duration: 0.3), value: isOffline)
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
                Image(systemName: "mappin")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.tertiaryFixed)
            }
            Triangle().fill(Color.tertiaryFixed).frame(width: 8, height: 5).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 104)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }
            Triangle().fill(Color.primaryFixed).frame(width: 10, height: 6).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 112)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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


// MARK: - Regroup Pin

struct RegroupPin: View {
    let type: String

    private var icon: String {
        switch type {
        case "FUEL":      return "fuelpump.fill"
        case "FOOD":      return "fork.knife"
        case "SCENIC":    return "camera.fill"
        default:          return "hand.raised.fill"
        }
    }

    private var accentColor: Color {
        switch type {
        case "FUEL":      return Color(red: 1.0, green: 0.63, blue: 0.0)   // amber
        case "FOOD":      return Color(red: 1.0, green: 0.43, blue: 0.0)   // orange
        case "SCENIC":    return Color(red: 0.01, green: 0.61, blue: 0.9)  // sky blue
        default:          return Color(red: 0.48, green: 0.11, blue: 0.64) // purple
        }
    }

    private var label: String {
        switch type {
        case "FUEL":      return "FUEL STOP"
        case "FOOD":      return "FOOD STOP"
        case "SCENIC":    return "SCENIC STOP"
        default:          return "STOP"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.surfaceDim)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(accentColor, lineWidth: 2.5))
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

// MARK: - Emergency Pin

/// Distinct from RegroupPin — an emergency is its own concept, not a regroup "type".
struct EmergencyPin: View {
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.errorColor)
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            Triangle().fill(Color.errorColor).frame(width: 8, height: 5).offset(y: -1)
            Text("EMERGENCY")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(0.5)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.errorColor.opacity(0.92))
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

// MARK: - Emergency Alert Banner

struct EmergencyAlertBanner: View {
    let reporterName: String
    let message: String
    /// nil for riders who aren't allowed to clear the emergency (only the raiser or leader can);
    /// the dismiss control is hidden for them and the banner stays until an authorized rider clears it.
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.errorColor)
                .frame(width: 36, height: 36)
                .background(Color.errorColor.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("EMERGENCY")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(Color.errorColor)
                    .tracking(1.5)
                Text("\(reporterName) needs help — head to their location")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceContainerHigh.opacity(0.6))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.errorContainer.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.6), lineWidth: 1.5))
        .shadow(color: Color.errorColor.opacity(0.3), radius: 10, y: 3)
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
