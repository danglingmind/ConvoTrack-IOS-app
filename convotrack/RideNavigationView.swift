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
    /// Whether the latest fix actually carried a speed solution. Separates "not moving" from
    /// "nothing known", which a bare `mySpeedKmh == 0` cannot: both used to render as "--", so the
    /// readout showed the same thing at a red light as it did before the GPS had said anything at
    /// all — and once that was fixed by always showing a number, a fix with no speed at all
    /// rendered as a confident "0 KM/H".
    @Published private(set) var hasSpeedFix = false
    /// Whether the rider is actually moving, for the follow camera and the broadcast cadence.
    /// Kept apart from `mySpeedKmh`, which is flattened to 0 under the display band and also reads
    /// 0 for a fix carrying no speed: both made a rider who was still riding look parked.
    @Published private(set) var isMoving = false
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
    /// When a usable `CLLocation.course` last arrived. Gates the compass fallback.
    private var lastCourseFixAt: Date? = nil
    /// Speed below which `CLLocation.course` stops being trustworthy (~5.4 km/h).
    private static let courseValidSpeedMps: Double = 1.5
    /// How far off the drawn route a fix may sit and still be snapped onto it.
    private static let snapMaxOffsetMeters: Double = 25
    /// Look-ahead along the route used to derive the road's bearing for the rider marker.
    private static let routeBearingLookaheadMeters: Double = 20
    /// Below this the rider is treated as stopped and the readout shows a flat 0.
    ///
    /// A GPS speed at rest does not settle on zero — it wanders by a metre or so a second, which
    /// is a couple of km/h, so a parked bike reads "3" then "1" then "4" forever. The band is set
    /// under a brisk walk, well below anything this app is ridden at.
    private static let stationarySpeedKmh: Double = 4
    /// Speed at which the rider counts as moving. Deliberately below `stationarySpeedKmh`: that
    /// band exists to stop a parked bike's readout flickering, not to decide whether the map keeps
    /// up with someone crawling through traffic.
    private static let movingSpeedKmh: Double = 2
    /// Displacement that counts as movement when a fix carries no speed solution. Well past the
    /// few metres a stationary fix wanders by, so a parked bike can't fake it.
    private static let movingDisplacementMeters: Double = 15
    /// Anchor for that displacement test. Held only while speed-less fixes are arriving.
    private var movementAnchor: CLLocation? = nil

    /// Speed for display, in km/h, or nil when the fix carries no speed solution at all.
    ///
    /// `CLLocation.speed` is negative when the fix carries no valid speed — not slow, but unknown
    /// — and collapsing that to 0 (by `max(0, …)` or by an early `return 0`, which is the same
    /// confident zero) makes Wi-Fi/cell-derived fixes, the Simulator's custom location and the
    /// first fixes after `startUpdatingLocation` all read "0 KM/H". Nil is what renders as "--".
    private static func displaySpeedKmh(from location: CLLocation) -> Double? {
        guard location.speed >= 0 else { return nil }
        let kmh = location.speed * 3.6
        return kmh < stationarySpeedKmh ? 0 : kmh
    }

    /// Refreshes `isMoving` from whichever signal this fix carries.
    private func updateMovementState(_ location: CLLocation) {
        if location.speed >= 0 {
            movementAnchor = nil
            isMoving = location.speed * 3.6 >= Self.movingSpeedKmh
            return
        }
        // No speed solution. Reading that as stopped left the follow camera parked for the whole
        // ride on any fix source that omits speed, so fall back to displacement, which needs none.
        guard let anchor = movementAnchor else {
            movementAnchor = location
            return
        }
        if location.distance(from: anchor) >= Self.movingDisplacementMeters {
            isMoving = true
            movementAnchor = location
        } else if location.timestamp.timeIntervalSince(anchor.timestamp) >= 10 {
            // 15 m unmet over ten seconds is under 5.4 km/h. Re-anchored so the window that
            // declares movement is always the recent one, not the whole ride.
            isMoving = false
            movementAnchor = location
        }
    }

    /// True when no usable course fix has arrived recently — you're stopped or crawling, and the
    /// compass is the only heading signal left worth showing.
    private var isCourseStale: Bool {
        guard let at = lastCourseFixAt else { return true }
        return Date().timeIntervalSince(at) > 5
    }
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
    /// Where the last FAST broadcast went out from, so a rider who has genuinely stopped can be
    /// told apart from one merely reading 0 km/h between two fixes. Deliberately not re-anchored
    /// by the slow stationary broadcasts: doing so reset the displacement every 10 s, which is
    /// what let a rider crawling below the bar stay latched on the slow cadence indefinitely.
    private var lastFastBroadcastLocation: CLLocation? = nil
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
    /// Perpendicular distance from the last fix to `navRoute`, as measured by `checkOffRoute`.
    /// The undebounced truth behind `isOffRoute`, and what gates polyline trimming.
    private var lastRouteOffsetMeters: Double = .infinity
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
            // Course owns the heading whenever it is fresh; the compass is a fallback for when
            // you're stopped. `CLHeading` reports where the PHONE points, which on a bike is
            // wherever the mount or the jacket pocket happens to face — and because this same
            // value also drives the camera bearing, letting the compass win swung the entire map
            // with the handlebars instead of following the road.
            guard self.isCourseStale else { return }
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
            .sink { [weak self] participants in
                guard let self else { return }
                self.staticParticipants = participants
                self.pruneDepartedRiders(roster: participants)
            }
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
    ///
    /// `from` bounds the search to segments at or after that index — see the monotone stamping in
    /// `stampAlongRouteDistances`. It defaults to 0, i.e. the whole route.
    private static func nearestPointOnRoute(
        _ route: [CLLocationCoordinate2D],
        to point: CLLocationCoordinate2D,
        from startIndex: Int = 0
    ) -> (segmentStart: Int, projected: CLLocationCoordinate2D) {
        let first = min(max(0, startIndex), max(0, route.count - 2))
        var bestIdx = first
        var bestProj = route[first]
        var bestDist = Double.infinity
        let cosLat = cos(point.latitude * .pi / 180)
        let px = point.longitude * cosLat, py = point.latitude
        for i in first..<route.count - 1 {
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
        let displaySpeed = Self.displaySpeedKmh(from: location)
        mySpeedKmh  = displaySpeed ?? 0
        hasSpeedFix = displaySpeed != nil
        updateMovementState(location)
        userLocation = location.coordinate
        // Course is derived from successive fixes, so below a walking pace it wanders wildly —
        // precisely when a rider is stopped at a light and would notice the map spinning. Above
        // the threshold it is the true direction of travel and outranks the compass.
        if location.course >= 0, location.speed >= Self.courseValidSpeedMps {
            userHeading = location.course
            lastCourseFixAt = Date()
        }
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

        // Gated on the MEASURED offset, not on the debounced `isOffRoute` flag. Clearing that
        // flag takes four consecutive on-route readings, so for ~4 s after a reroute landed — or
        // after a jitter spike cleared — the head stayed frozen wherever it was last cut while the
        // rider drove on, detaching it from the marker for exactly as long as the debounce ran.
        // Proximity to the route we are following is the real precondition for trimming it.
        if lastRouteOffsetMeters <= offRouteThresholdMeters { trimActiveRoute(to: location) }

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

        // Parked riders broadcast on a slower cadence. Now that fixes arrive at a steady 1 Hz
        // whether or not the bike is moving, a flat 2 s interval would have a bike left outside a
        // café posting an unchanged coordinate every two seconds for as long as the ride is open.
        // Nothing depends on that: presence runs off its own 5 s `ride:heartbeat`, and a stopped
        // rider's progress and leaderboard position are by definition not changing.
        //
        // Both halves of the test used to latch a moving rider onto the slow cadence. The speed
        // came from the band-flattened `mySpeedKmh`, so anything under 4 km/h read as parked; and
        // the displacement was measured from the last broadcast of ANY kind, re-anchored on every
        // slow tick, so a ~3 km/h crawl covering ~8 m per 10 s interval never accumulated past the
        // 10 m bar. Everyone else's pin, leaderboard distance and edge indicator for that rider
        // then lagged by up to 10 s, in exactly the dense traffic where the pack needs them live.
        let isStationary = !isMoving
            && lastFastBroadcastLocation.map { location.distance(from: $0) < 10 } ?? false
        let interval: TimeInterval = isStationary ? 10.0 : 2.0
        guard now.timeIntervalSince(lastBroadcastDate) >= interval else { return }
        lastBroadcastDate = now
        // Anchored on the last FAST broadcast only, so displacement accumulates across slow ticks
        // and sustained movement escapes the slow cadence on its own.
        if !isStationary { lastFastBroadcastLocation = location }
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

    /// Drops riders who have left the ride from the derived state that doesn't otherwise rebuild
    /// from the roster.
    ///
    /// `handleStateUpdate` reconciles both `leaderboardRows` and `riders` against the roster
    /// already — but only inside `if !update.leaderboard.isEmpty`, and the server's leaderboard is
    /// empty for the entire window between a ride starting and the first location tick landing.
    /// A rider leaving inside that window would otherwise stay in everyone else's leaderboard,
    /// live-rider count, map pin set and off-screen indicators until somebody's GPS moved.
    ///
    /// Driven off `ride:participant_left`, which the server emits BEFORE the accompanying
    /// `ride:state_update` — so by the time a state update is applied, the departed rider is
    /// already out of the roster this prunes against.
    private func pruneDepartedRiders(roster: [RideParticipant]) {
        // An empty roster is a transient socket state (a reconnect mid-flight), not "everyone
        // left". Never prune on it — that would blank the HUD for a moment on every drop.
        guard !roster.isEmpty else { return }
        var present = Set(roster.map(\.userId))
        present.insert(myUserId)
        leaderboardRows.removeAll { !present.contains($0.id) }
        riders.removeAll { !present.contains($0.id) }
        // Also forget their last position, so the "keep offline riders pinned where they dropped"
        // path in `handleStateUpdate` can't resurrect a ghost pin for someone who has left.
        lastKnownRiderPositions = lastKnownRiderPositions.filter { present.contains($0.key) }
    }

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
                steps += Self.makeNavSteps(from: result.steps)
            }
            cumulativeStopTimes.append(totalTime)
        }

        // Draw and track the leader-selected route geometry when available; the steps above (turn
        // instructions) come from the live recompute.
        //
        // The stored polyline is not merely the prettier line to draw — it is the one the SERVER
        // measures everyone against. `progressEngine.computeProgress` derives both `progress` and
        // `offRoute` from `ride.route_polyline`, so any geometry the client follows instead puts
        // it in disagreement with the server about where every rider is. It is never swapped out
        // below; only the instructions stamped onto it can be dropped.
        let storedRoute = GoogleDirectionsService.decodedRoute(polyline)
        let geometry = storedRoute ?? allCoords

        // …but only once the two are known to describe the SAME roads.
        //
        // A ride stores the leader's pick as a bare polyline, and the leader may well have chosen
        // an alternative rather than Google's default. The recompute above always asks for the
        // default, so on such a ride `steps` described one road while `geometry` drew another, and
        // stamping those step ends onto this polyline projected each turn onto whatever point of
        // the leader's route happened to lie nearest — instructions for roads the rider was never
        // on, at distances that meant nothing. A recompute can also drift on its own: traffic
        // moves Google's first choice between the moment a ride is created and the moment it
        // starts.
        if let stored = storedRoute, !allCoords.isEmpty,
           Self.routeDeviation(of: allCoords, from: stored) > Self.routeMatchToleranceMeters {
            // Ask for the same alternative set the leader chose from and take the steps of the one
            // that traces the stored shape. Only meaningful on a single-leg ride — Google returns
            // no alternatives once intermediate waypoints are present, which is also the only case
            // `CreateRideView` offers a choice in.
            let matched: DirectionsResult? = sorted.count == 2
                ? await Self.alternativeMatching(
                    stored,
                    from: CLLocationCoordinate2D(latitude: sorted[0].lat, longitude: sorted[0].lng),
                    to:   CLLocationCoordinate2D(latitude: sorted[1].lat, longitude: sorted[1].lng))
                : nil

            if let matched {
                steps               = Self.makeNavSteps(from: matched.steps)
                totalTime           = matched.durationSeconds
                cumulativeStopTimes = [matched.durationSeconds]
            } else {
                // No instruction set could be matched to the line the leader drew — always the
                // case on a multi-stop ride, where there is no alternative set to search. Drop
                // the turns rather than the geometry: the banner falls back to "Follow route",
                // while following `allCoords` instead would have every rider dead on the drawn
                // line reported `offRoute: true` by the server, ranked off a progress figure
                // measured on a different road, and charged the gap as `detourMeters` in the
                // ride summary. Reciting no turns beats reciting another road's turns, and both
                // beat silently disagreeing with the server about where everyone is.
                //
                // `totalTime` stays the recompute's: it is only the bootstrap ETA until the first
                // traffic-aware refresh lands, and both roads run between the same stops.
                steps = []
            }
        }

        // Step ends are projected onto the geometry we actually follow rather than assumed to lie
        // on it: even the matching route is a fresh response whose vertices need not coincide with
        // the stored polyline's.
        adoptNavRoute(geometry, steps: steps)

        // `adoptNavRoute` above already set navRoute / its prefix distances / navSegmentIndex.
        // The dim planned layer and the followed line are the same polyline at ride start; they
        // only part company once a reroute lands, which `calculateFullReroute` handles.
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

        // First step that still ends ahead of us.
        //
        // No slack. It used to carry 5 m, to stop a rider parked exactly on a step boundary
        // flickering between two steps — which the forward-only clamp below already makes
        // impossible, and which cost the banner its last 5 m before every junction: the index
        // advanced just short of the turn, so the moment the instruction mattered most it had
        // already moved on to the one after it. Google holds the current maneuver until you are
        // through the junction.
        let computed = navSteps.firstIndex { $0.endDistanceAlongRoute > progress }
            ?? navSteps.count - 1
        // Forward-only, mirroring the route progress index it is derived from.
        currentStepIndex = max(currentStepIndex, computed)

        let banner = Self.upcomingBanner(steps: navSteps, currentIndex: currentStepIndex)
        // Along-route rather than straight-line: "300 m" should mean 300 m of driving, which is
        // what Google shows and what actually matters around a curve.
        distanceToNextTurnMeters = max(0, banner.junctionDistanceAlongRoute - progress)
        currentInstruction = banner.instruction
        currentManeuver    = banner.maneuver
    }

    /// The maneuver to announce next, and how far along the route it is performed.
    ///
    /// A Routes API step's `navigationInstruction` describes the maneuver taken to ENTER that
    /// step, not one taken at its end: "Turn right onto Ring Rd" belongs to the step that runs
    /// ALONG Ring Rd, and the turn itself sits at that step's START — which is the END of the step
    /// before it. Showing the CURRENT step's own instruction therefore announced the turn the
    /// rider had already made, while pairing it with the distance to the next junction: the banner
    /// read "Head north on MG Rd — 400 m" exactly where Google Maps reads "Turn right onto Ring Rd
    /// — 400 m". Every instruction on the ride was one maneuver behind, which is why the guidance
    /// never matched Google's.
    ///
    /// So the text comes from the step AFTER the current one, and the distance from the end of the
    /// step immediately before that text's step — the junction where it is actually performed.
    /// The two are returned together because steps with no instruction text still occupy real
    /// distance: skipping forward over them moves the junction too, and reading the distance off
    /// `currentIndex` independently would re-introduce the same mispairing at a smaller scale.
    private static func upcomingBanner(
        steps: [NavStep], currentIndex: Int
    ) -> (instruction: String, maneuver: String, junctionDistanceAlongRoute: Double) {
        guard let last = steps.last else { return ("", "", 0) }
        if currentIndex + 1 < steps.count {
            for j in (currentIndex + 1)..<steps.count where !steps[j].instruction.isEmpty {
                return (steps[j].instruction, steps[j].maneuver ?? "", steps[j - 1].endDistanceAlongRoute)
            }
        }
        // No maneuver left ahead — what remains is the arrival. The last step ends at the
        // destination, so its along-route end is genuinely the distance still to ride.
        return ("Arrive at destination", "ARRIVE", last.endDistanceAlongRoute)
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

    private static func makeNavSteps(from steps: [DirectionsStep]) -> [NavStep] {
        // Every step is kept, including any without instruction text: they still occupy real
        // distance, and dropping them breaks the chain of along-route positions. `upcomingBanner`
        // walks past the textless ones for display.
        steps.map {
            NavStep(instruction: $0.instruction, maneuver: $0.maneuver,
                    endCoordinate: $0.endCoordinate, distanceMeters: $0.distanceMeters,
                    endDistanceAlongRoute: 0)   // stamped once the geometry is known
        }
    }

    /// How far apart two routes can sit and still count as the same roads. Comfortably above the
    /// few metres two responses for one road differ by (HIGH_QUALITY vertices, lane snapping,
    /// traffic-shifted geometry), and far below the separation of two genuinely different
    /// alternatives, which part company by whole blocks.
    private static let routeMatchToleranceMeters: Double = 60

    /// How closely `candidate` traces `reference`: the 90th-percentile distance, in metres, from
    /// points sampled evenly along `candidate` to the nearest point on `reference`.
    ///
    /// A percentile rather than the maximum, so one clipped corner or a differently-modelled
    /// junction approach can't condemn an otherwise identical route.
    ///
    /// Runs its own flat-earth arithmetic instead of reusing `nearestPointOnRoute`. This compares
    /// every sample against every segment of the reference — 64 × several thousand on a long ride
    /// — and that helper allocates two `CLLocation` objects per segment to take a geodesic
    /// distance. Half a million short-lived objects on the main actor is a visible stall at the
    /// moment navigation opens, to decide a question whose answer is "same road or a different
    /// one". Metres here are equirectangular about the route's mid-latitude: good to a fraction of
    /// a percent over a ride's span, against a 60 m tolerance.
    private static func routeDeviation(of candidate: [CLLocationCoordinate2D],
                                       from reference: [CLLocationCoordinate2D]) -> Double {
        guard candidate.count >= 2, reference.count >= 2 else { return .infinity }

        let anchor = reference[reference.count / 2]
        let metresPerLat = 111_132.0
        let metresPerLng = 111_320.0 * cos(anchor.latitude * .pi / 180)
        func project(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - anchor.longitude) * metresPerLng,
             (c.latitude  - anchor.latitude)  * metresPerLat)
        }
        let ref = reference.map(project)

        let sampleCount = 64
        var deviations: [Double] = []
        deviations.reserveCapacity(sampleCount)
        for k in 0..<sampleCount {
            let idx = Int((Double(k) / Double(sampleCount - 1)) * Double(candidate.count - 1))
            let p = project(candidate[idx])
            var bestSquared = Double.infinity
            for i in 0..<ref.count - 1 {
                let a = ref[i], b = ref[i + 1]
                let dx = b.x - a.x, dy = b.y - a.y
                let lenSq = dx * dx + dy * dy
                let t = lenSq < 1e-9 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
                let ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy)
                let squared = ex * ex + ey * ey
                if squared < bestSquared { bestSquared = squared }
            }
            deviations.append(bestSquared.squareRoot())
        }
        deviations.sort()
        return deviations[Int((Double(deviations.count) - 1) * 0.9)]
    }

    /// The alternative for `origin`→`destination` that traces `stored`, or nil when none of them
    /// does. Nil is a real answer, not just a failure: the stored polyline may predate a road
    /// change, or have been trimmed, and guessing an alternative in that case would put the wrong
    /// turns on screen — the exact failure this lookup exists to prevent.
    ///
    /// Tried against two alternative sets, because either one alone misses matches the other
    /// finds. TRAFFIC_AWARE first: that is the set `CreateRideView` showed the leader, so it is
    /// the one their pick provably came from. But Google composes it from live conditions, and a
    /// ride started hours after it was created is asking a different question of a different road
    /// network — the traffic-motivated alternative the leader chose at 9am need not be offered at
    /// noon. TRAFFIC_UNAWARE is the time-invariant road-network set, so it is the stable second
    /// chance. The cost is one extra Routes API call, and only on rides that would otherwise lose
    /// their turn guidance entirely.
    private static func alternativeMatching(
        _ stored: [CLLocationCoordinate2D],
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> DirectionsResult? {
        for trafficAware in [true, false] {
            guard let options = try? await GoogleDirectionsService.alternativeRoutesWithSteps(
                from: origin, to: destination, trafficAware: trafficAware
            ) else { continue }
            let scored = options
                .filter { !$0.steps.isEmpty }
                .map { (route: $0, deviation: routeDeviation(of: $0.coordinates, from: stored)) }
            if let best = scored.min(by: { $0.deviation < $1.deviation }),
               best.deviation <= routeMatchToleranceMeters {
                return best.route
            }
        }
        return nil
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
        var searchFrom = 0
        for var step in steps {
            // Forward-only search. A whole-route scan puts each step end on whichever pass of a
            // route that comes back on itself — a loop, an out-and-back, a cloverleaf, a pair of
            // parallel carriageways — happens to lie nearest, which can land a late turn behind an
            // early one. The clamp below then flattens it and every step after it onto the same
            // distance, so a whole run of maneuvers fires at once at the wrong junction. Steps are
            // ordered along the route by definition, so step k's match cannot precede step k-1's.
            let (segIdx, projected) = nearestPointOnRoute(route, to: step.endCoordinate, from: searchFrom)
            let a = CLLocation(latitude: route[segIdx].latitude, longitude: route[segIdx].longitude)
            let along = cumulative[segIdx] + a.distance(
                from: CLLocation(latitude: projected.latitude, longitude: projected.longitude)
            )
            step.endDistanceAlongRoute = min(max(along, previous), total)
            previous = step.endDistanceAlongRoute
            searchFrom = segIdx
            stamped.append(step)
        }
        // The last step ends at the destination by definition; snapping it there stops a slightly
        // short projection from leaving the final instruction unreachable.
        if !stamped.isEmpty {
            stamped[stamped.count - 1].endDistanceAlongRoute = total
        }
        return stamped
    }

    /// Projects `point` onto the segment a→b in a local flat-earth frame.
    ///
    /// Returns the clamped foot of the perpendicular, the segment parameter `t` (0 = at `a`,
    /// 1 = at `b`), and the metric distance from `point` to that foot. `t` matters to callers as
    /// much as the point does: `t == 1` means the projection ran off the far end, i.e. the rider
    /// is already PAST this segment — which is how `advanceRouteProgress` tells "sitting on this
    /// segment" apart from "near its end, heading away".
    ///
    /// One implementation for all three former copies of this math (progress tracking, route
    /// trimming, off-route distance), so they cannot disagree about where the rider is.
    private static func segmentProjection(
        of point: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> (point: CLLocationCoordinate2D, t: Double, distance: Double) {
        let cosLat = cos(a.latitude * .pi / 180)
        let ax = a.longitude * cosLat, ay = a.latitude
        let bx = b.longitude * cosLat, by = b.latitude
        let px = point.longitude * cosLat, py = point.latitude
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        let t = lenSq < 1e-18 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        let foot = CLLocationCoordinate2D(
            latitude:  a.latitude  + t * (b.latitude  - a.latitude),
            longitude: a.longitude + t * (b.longitude - a.longitude)
        )
        let distance = CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: foot.latitude, longitude: foot.longitude))
        return (foot, t, distance)
    }

    /// Closest point to `point` on the segment a→b.
    private static func projectOntoSegment(
        _ point: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        segmentProjection(of: point, a: a, b: b).point
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
        lastRouteOffsetMeters = minimumDistanceToUpcomingRoute(from: location)
        let rawOffRoute = lastRouteOffsetMeters > offRouteThresholdMeters

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
            steps += Self.makeNavSteps(from: result.steps)
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
        let banner = Self.upcomingBanner(steps: navSteps, currentIndex: 0)
        currentInstruction       = banner.instruction
        currentManeuver          = banner.maneuver
        distanceToNextTurnMeters = banner.junctionDistanceAlongRoute
    }

    /// Advance `navSegmentIndex` to the closest upcoming segment, never backwards.
    private func advanceRouteProgress(to location: CLLocation) {
        guard navRoute.count >= 2 else { return }
        let lookEnd = min(navRoute.count - 2, navSegmentIndex + 200)
        guard lookEnd >= navSegmentIndex else { return }

        var minDist = Double.infinity
        var bestIdx = navSegmentIndex
        for i in navSegmentIndex...lookEnd {
            let hit = Self.segmentProjection(of: location.coordinate, a: navRoute[i], b: navRoute[i + 1])
            if hit.distance < minDist { minDist = hit.distance; bestIdx = i }
            // Stop early only when the rider is sitting ON this segment — `t < 1` — not merely
            // close to its far endpoint. The old `minDist < 5` break tested proximity alone, so on
            // dense curve geometry (Google polylines run 2–3 m per vertex through a bend) the very
            // first segment tried, the one already behind the rider, kept satisfying it and the
            // index never advanced. `trimActiveRoute` then clamped the polyline head to a vertex
            // the rider had already driven through: the bright line's start stalled while the
            // chevron carried on, then jumped to catch up — the disjointed, uneven-pace head this
            // search feeds.
            if hit.distance < 5 && hit.t < 0.999 { break }
        }
        // Only advance if user is actually near the route — prevents a far-away GPS fix
        // from jumping the index to the end of a short route, which caused the straight-line bug.
        if bestIdx > navSegmentIndex && minDist <= 80 {
            navSegmentIndex = bestIdx
        }
    }

    /// Places the rider marker AND cuts the bright polyline to start underneath it — one call,
    /// one point, so the two cannot disagree.
    ///
    /// They used to be decided separately: the polyline always started at `projected` (the foot of
    /// the perpendicular onto the route) while the marker took `projected` only when the fix sat
    /// within `snapMaxOffsetMeters` of the line and otherwise kept the raw GPS coordinate. Every
    /// fix that failed that test — routine on a wide road, a flyover, or beside a service lane,
    /// where lane offset plus GPS error clears 25 m easily — detached the marker from the line's
    /// head, and because the raw fix jitters while the snapped head glides, the two visibly moved
    /// at different paces. The head and the marker are now the same coordinate by construction.
    ///
    /// When the fix is too far off the line to claim a snap, the marker honestly stays on the raw
    /// coordinate and the polyline is drawn from there back onto the road: still one connected
    /// line starting at the chevron, rather than two things floating apart.
    private func trimActiveRoute(to location: CLLocation) {
        guard navRoute.count >= 2 else { return }
        let i    = navSegmentIndex
        let next = min(i + 1, navRoute.count - 1)

        let hit = Self.segmentProjection(of: location.coordinate, a: navRoute[i], b: navRoute[next])
        // A wild fix inside an on-route run must not be yanked onto the line — the off-route flag
        // needs three consecutive readings to trip, so this bound is what stops us claiming
        // precision we don't have in between.
        let snapped = hit.distance <= Self.snapMaxOffsetMeters
        let head = snapped ? hit.point : location.coordinate

        userLocation = head

        // Point along the ROAD, not along the course. `location.course` is derived from
        // successive fixes, so it weaves with the lane and with noise — the arrow sat a few
        // degrees askew on a line it was sitting exactly on. The camera takes its bearing from
        // this same value, so the map steadies with it. Only meaningful while snapped: off the
        // line, the road ahead is not the direction the rider is going.
        if snapped, location.speed >= Self.courseValidSpeedMps,
           let bearing = routeBearingAhead(from: hit.point) {
            userHeading = bearing
            // Counts as a fresh heading for `isCourseStale`, otherwise the compass fallback would
            // wake up five seconds in and start fighting the road bearing.
            lastCourseFixAt = Date()
        }

        var trimmed: [CLLocationCoordinate2D] = [head]
        if !snapped { trimmed.append(hit.point) }   // short leader from the marker back to the road
        if next < navRoute.count { trimmed.append(contentsOf: navRoute[next...]) }
        activeRouteCoordinates = trimmed
    }

    /// Bearing of the road ahead: from `projected` to a point roughly
    /// `routeBearingLookaheadMeters` further along `navRoute`.
    ///
    /// Measured over a look-ahead rather than from the single segment under the rider because
    /// route polylines are dense — a 2–3 m segment's bearing swings hard from vertex to vertex,
    /// which would make the chevron (and the camera) twitch on every fix.
    private func routeBearingAhead(from projected: CLLocationCoordinate2D) -> Double? {
        guard navRoute.count >= 2 else { return nil }
        var remaining = Self.routeBearingLookaheadMeters
        var cursor = projected
        var i = navSegmentIndex + 1
        while i < navRoute.count {
            let next = navRoute[i]
            let step = CLLocation(latitude: cursor.latitude, longitude: cursor.longitude)
                .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
            if step >= remaining || i == navRoute.count - 1 {
                return Self.bearing(from: projected, to: next)
            }
            remaining -= step
            cursor = next
            i += 1
        }
        return nil
    }

    /// Initial great-circle bearing from `a` to `b`, in degrees clockwise from true north —
    /// the same convention as `CLLocation.course` and `GMSMarker.rotation`.
    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude  * .pi / 180
        let lat2 = b.latitude  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
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
        Self.segmentProjection(of: point.coordinate, a: a, b: b).distance
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
    /// Width the landscape side panel occupies; the map reserves it so nothing bleeds behind.
    @State private var measuredPanelWidth: CGFloat = 0
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
            // Two outcomes, not one. Exit is listed first and is not destructive: it is the
            // common case, and since the navigation screen no longer carries a back button it is
            // now the ONLY way for a leader to step off this screen without ending everyone's
            // ride. End Ride keeps the destructive role and stays irreversible.
            .confirmationDialog(
                "Leave navigation or end the ride?",
                isPresented: $showEndConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit Navigation") { dismiss() }
                Button("End Ride", role: .destructive) { Task { await vm.endRide() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Exit closes navigation on your phone — the ride keeps running and you can resume from the lobby. End Ride stops location sharing for every rider and generates the summary; that can't be undone.")
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
            // Landscape: the reader must span the FULL screen width, not the safe-area width.
            // Measured on device, it was ending ~62pt short of the right edge — so the panel's
            // frame stopped there too, and its 9pt gutter was measured from the wrong place,
            // leaving a 71pt strip. Ignoring the horizontal insets here makes `proxy.size.width`
            // the real width, so the panel is a true third and sits flush against the edge.
            // Portrait is unaffected: an empty edge set is a no-op.
            GeometryReader { proxy in
                if isLandscape {
                    landscapeHud(proxy)
                        .onGeometryChange(for: CGFloat.self) { _ in
                            landscapePanelWidth(proxy.size.width)
                        } action: { width in
                            measuredPanelWidth = width
                        }
                } else {
                    hudLayer(bottomInset: proxy.safeAreaInsets.bottom)
                }
            }
            .ignoresSafeArea(edges: isLandscape ? .horizontal : [])
            if isLandscape {
                // Only before navigation starts. Once it is live, leaving happens through the
                // end-ride confirmation's Exit option — same rule as portrait, so the two
                // orientations offer the same way out.
                if !isNavigationActive { landscapeBackButton }
                if isNavigationActive && isFreeLooking { landscapeResumeButton }
            }
        }
        // One coordinate space for the whole screen in landscape. Without this the map's
        // `.padding(.trailing, panelWidth)` reserved the panel's width starting from the SAFE-AREA
        // edge, i.e. ~59pt inboard, so the map stopped short and left a black stripe between it and
        // the sidebar. Ignoring the horizontal insets here makes map, panel and overlays all
        // measure from the same physical edges. No-op in portrait.
        .ignoresSafeArea(edges: isLandscape ? .horizontal : [])
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
        // The chrome measures 0 until the first layout pass lands, so a route that resolved
        // before then was framed with no top inset at all. Re-fit when the real numbers arrive
        // (and again on rotation, when they change) — but only while the preview owns the
        // camera; once navigation is live the follow camera does, and must not be yanked.
        .onChange(of: topChromeBottom) { _, _ in handleRouteVersionChanged() }
        .onChange(of: bottomBarHeight) { _, _ in handleRouteVersionChanged() }
        .onChange(of: vm.locationTick) { old, _ in handleLocationTickChanged(wasZero: old == 0) }
    }

    // MARK: - Load

    private func loadAndSetup() async {
        // Retried: this screen loads exactly once, and `vm.setup` is what starts the route,
        // the location stream and the follow camera. A single failed fetch with no cached ride
        // to fall back on fell straight through the guard below and left the screen frozen on a
        // dead map preview — no route line, no rider pin, no error, and no way to retry short of
        // backing out of the ride.
        let fetched = await APIClient.shared.getRideRetrying(rideId)
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
            // The active route is trimmed to start under the chevron every fix, so its head is
            // the rider — not an endpoint that wants a cap of its own.
            isNavigating: true,
            onInteraction: onMapInteraction,
            onEdgeIndicators: { edgeIndicators = $0 },
            // Landscape moves the chrome off the map entirely, so there is nothing to clamp under.
            topOverlayHeight: isNavigationActive && !isLandscape ? topChromeBottom : 0
        )
        // Portrait bleeds under the notch and sides but NOT the bottom: there the bottom edge is
        // set by the measured bar height, and ignoring the bottom safe area would expand the map
        // back over that bar.
        //
        // Landscape has no bottom bar, so withholding the bottom edge just left the home-indicator
        // inset showing as a black stripe under the map. It bleeds all the way there — the side
        // panel paints its own background over the same region, so nothing is left uncovered.
        .ignoresSafeArea(edges: isLandscape ? .all : [.top, .horizontal])
        // Exactly one reservation applies: landscape puts the HUD in a right-hand panel, portrait
        // in a bottom bar. Reserving the other one too would shrink the map for no reason.
        .padding(.bottom, isLandscape ? 0 : bottomBarHeight)
        .padding(.trailing, isLandscape ? measuredPanelWidth : 0)
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
            fitRoutePreview(vm.routeCoordinates)
        } else if let dest = vm.destinationCoordinate {
            cameraCommand = MapCameraCommand.focus(lat: dest.latitude, lng: dest.longitude, zoom: 11)
        }
    }

    /// Frames the whole route in the pre-navigation preview, inside the band the chrome
    /// actually leaves visible — the same treatment the lobby's preview gets.
    ///
    /// The top inset is the measured chrome plus `stopPinTopExtent`, not a bare 80. Stop pins
    /// are bottom-anchored, so a destination sitting at the route's northern edge towers its
    /// full baked height (up to 92pt with a wrapped name) ABOVE the coordinate `GMSCameraUpdate`
    /// framed — and the back button / "TO …" row covers more of the map on top of that. The old
    /// constant reserved for neither, so that pin was cut off by the top of the viewport.
    @MainActor
    private func fitRoutePreview(_ coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        cameraCommand = MapCameraCommand.fitRouteInsets(
            coords,
            top:    topChromeBottom + GoogleMapView.stopPinTopExtent + 8,
            left:   44,
            // Clears the navigation preview bar, which floats over the map.
            bottom: max(bottomBarHeight, 200) + 8,
            right:  44,
            animated: true
        )
    }

    private func handleLocationTickChanged(wasZero: Bool) {
        guard let coord = vm.userLocation else { return }
        guard isNavigationActive else { return }
        // Track speed on every tick — including the ones that don't move the camera — so the
        // zoom is already correct whenever a camera command does go out.
        cameraSpeedKmh = wasZero ? vm.mySpeedKmh : cameraSpeedKmh + 0.25 * (vm.mySpeedKmh - cameraSpeedKmh)
        // From the view model's own movement signal, not the readout. `mySpeedKmh` is zeroed below
        // the 4 km/h display band, so `> 0` silently meant "> 4 km/h": between 2 and 4 the map
        // stopped re-centring on a rider still creeping forward, and if they had panned,
        // `isFreeLooking` never auto-cleared and the viewport stayed frozen behind them.
        let isMoving    = vm.isMoving
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

    // MARK: - Landscape side panel
    //
    // Landscape has ~390pt of height and ~850pt of width, so a full-width bottom bar spends the
    // scarce dimension and wastes the plentiful one. The screen is split in thirds instead: the map
    // keeps the left two, every HUD element moves into the right one. Portrait is untouched — it
    // still renders `hudLayer` exactly as before.

    /// Width of the side panel. The map is padded by this so it never draws behind the panel.
    private func landscapePanelWidth(_ total: CGFloat) -> CGFloat { (total / 3).rounded() }

    private func landscapeHud(_ proxy: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)                       // the map owns the left two thirds
            landscapePanel(safeArea: proxy.safeAreaInsets)
                .frame(width: landscapePanelWidth(proxy.size.width))
        }
    }

    /// RESUME floating over the MAP at bottom-centre — the same place it sits in portrait, and
    /// where a rider looks for it after panning. Centring is over the map only, so the trailing
    /// padding is the panel's width.
    private var landscapeResumeButton: some View {
        Button(action: resumeNavigation) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").font(.system(size: 11, weight: .bold))
                Text("RESUME").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.2)
            }
            .foregroundColor(Color.onPrimaryFixed)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.primaryFixed)
            .clipShape(Capsule())
            .shadow(color: Color.primaryFixed.opacity(0.55), radius: 10)
        }
        .padding(.trailing, measuredPanelWidth)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .transition(.scale.combined(with: .opacity))
    }

    /// Back button floating over the map, landscape only.
    ///
    /// Deliberately NOT inside the HUD's `GeometryReader`: that reader sits beside a map which
    /// ignores the safe area, so what it reports as its leading edge is not the screen's — padding
    /// measured from it pushed the button ~60pt inboard. This shares the map's own coordinate
    /// space instead (`ignoresSafeArea(edges: [.top, .horizontal])`, the same edges the map
    /// ignores), so 16pt means 16pt from the physical screen edge, the standard iOS margin.
    ///
    /// Sitting at the top is what makes that safe with a notch on this side: in landscape the
    /// camera housing is a band in the VERTICAL middle of the edge, so a control pinned to the top
    /// corner clears it without needing the full inset.
    private var landscapeBackButton: some View {
        backButton
            .padding(.leading, 21)   // standard 16pt margin, nudged 5 to sit right of the corner
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(edges: [.top, .horizontal])
    }

    private func landscapePanel(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 10) {
            if isNavigationActive {
                // 1 — turn-by-turn, alone on its row. The rider count that used to share it moved
                // into the leaderboard row below, which is what lets the banner run the full width
                // of the panel at a size readable from a mount.
                turnInstructionCard(expand: true)

                // 2 — leaderboard, horizontally scrolled, with the rider count pinned trailing.
                landscapeLeaderboardStrip

                // 3 — banners, directly under the leaderboard.
                landscapeTransientStack

                Spacer(minLength: 0)

                // 4 + 5 — stats and actions stick to the bottom, so they stay under the rider's
                // thumb and don't shuffle when a banner appears above them.
                landscapeStatsRow
                landscapeButtonsRow
            } else {
                navigationPreviewBar
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 9)
        // Full width inside the bar: the same 9pt gutter as the leading edge, no notch allowance.
        //
        // That is safe for these rows because in landscape the camera housing is a band in the
        // VERTICAL middle of the edge, and every row sits above it (turn card, leaderboard) or
        // below it (stats, actions). The one thing that could reach into that band is a tall stack
        // of banners, which would pass under the housing rather than beside it.
        .padding(.trailing, 9)
        .padding(.top, safeArea.top + 10)
        .padding(.bottom, safeArea.bottom + 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.surfaceDim.opacity(0.55)
            }
            .ignoresSafeArea()
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.outlineVariant.opacity(0.25)).frame(width: 1)
        }
    }

    /// Regroup and end-ride, equal width across the panel. Portrait keeps its square icon buttons;
    /// here the panel is the only chrome, so the actions get the full width of it.
    private var landscapeButtonsRow: some View {
        HStack(spacing: 10) {
            Button(action: { showRegroup = true }) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonSize)
                    .background(Color.surfaceContainerHigh.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
            }
            Button(action: {
                // Same rule as portrait: the leader confirms, everyone else just leaves the screen.
                if vm.amILeader { showEndConfirm = true } else { dismiss() }
            }) {
                Group {
                    if vm.isEnding {
                        ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                    } else {
                        Image(systemName: "stop.fill").font(.system(size: 18))
                    }
                }
                .foregroundColor(Color.errorColor)
                .frame(maxWidth: .infinity)
                .frame(height: buttonSize)
                .background(Color.errorContainer.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
            }
            .disabled(vm.isEnding)
        }
    }

    /// Stats on their own row. Same `barStat`/`barDivider` the portrait bar uses; units are dropped
    /// because a third of the width can't hold them beside three values.
    private var landscapeStatsRow: some View {
        HStack(spacing: 10) {
            barStat(label: "SPEED", value: vm.hasSpeedFix ? String(format: "%.0f", vm.mySpeedKmh) : "--", unit: nil)
            barDivider
            barStat(label: "ETA", value: vm.etaString, unit: nil)
            barDivider
            barStat(label: "DIST", value: vm.myDistanceToGoalKm > 0 ? String(format: "%.1f", vm.myDistanceToGoalKm) : "--", unit: nil)
            Spacer(minLength: 0)
        }
    }

    /// Banners, alerts and the resume/arrived controls — everything that appears only sometimes.
    @ViewBuilder
    private var landscapeTransientStack: some View {
        VStack(spacing: 8) {
            if vm.connectionState == .reconnecting {
                ConnectionBanner(state: vm.connectionState)
            }
            if vm.isOffRoute {
                HStack { offRouteBanner; Spacer(minLength: 0) }
            }
            if let emergency = vm.activeEmergency {
                EmergencyAlertBanner(
                    reporterName: vm.emergencyReporterName,
                    message: emergency.message,
                    // Same rule as portrait: no dismiss control unless you raised it or lead.
                    onDismiss: vm.canDismissEmergency ? { vm.dismissEmergency() } : nil
                )
            }
            if vm.showSplitAlert {
                GroupSplitAlert(
                    onIgnore: { withAnimation(.spring()) { vm.showSplitAlert = false } },
                    onRegroup: { showRegroup = true }
                )
            }
            if vm.showRegroupToast, let regroup = vm.activeRegroup {
                RegroupToastBanner(type: regroup.type)
            }
            if vm.activeRegroup != nil {
                if vm.hasMarkedArrived { waitingForOthersPill } else { arrivedButton }
            }
        }
        .animation(.spring(response: 0.3), value: vm.showSplitAlert)
        .animation(.spring(response: 0.3), value: isFreeLooking)
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

    /// Shared by portrait's top bar and the landscape side panel, so the two can't drift.
    private var backButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.onSurface)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        }
    }

    private var liveRiderCountPill: some View {
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
    }

    /// Portrait top chrome. (Landscape never renders this — `coreView` swaps in `landscapeHud`,
    /// which builds its own column in `landscapePanel`.)
    private var topBar: some View {
        VStack(spacing: 8) {
            if isNavigationActive {
                // The turn banner has the row to itself. The back button and the rider-count pill
                // that used to flank it are gone: exiting now happens through the end-ride
                // confirmation, and the count moved into the leaderboard row below.
                turnInstructionCard(expand: true)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Route preview. There is no turn banner yet, and this back button is the only way
                // back to the lobby before navigation starts — the end-ride control that replaces
                // it only exists once navigation is live — so it stays put here.
                HStack(alignment: .center, spacing: 10) {
                    backButton
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
                    Spacer()
                }
                .padding(.horizontal, 20)   // matches the banners below and the bottom bar
                .transition(.opacity)
            }

            if isNavigationActive {
                leaderboardStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.35), value: isNavigationActive)
    }

    /// The turn-by-turn banner.
    ///
    /// It owns its whole row now in both orientations — the back button and the live-rider pill
    /// moved out (exit lives in the end-ride confirmation, the count in the leaderboard row) — and
    /// that reclaimed width is what pays for these sizes. Previously it was squeezed into ~241pt
    /// of a 353pt row, leaving ~177pt for text, which is why the distance sat at 10pt and the
    /// street name at 12pt: unreadable at road speed, which is the only speed it is read at.
    ///
    /// Landscape runs one step smaller across the board: the side panel is a third of the width
    /// and the whole HUD has to fit in ~390pt of height, so the same numbers would crowd the
    /// leaderboard and stats out of the panel.
    private func turnInstructionCard(expand: Bool) -> some View {
        let tile:     CGFloat = isLandscape ? 46 : 52
        let glyph:    CGFloat = isLandscape ? 21 : 24
        let distance: CGFloat = isLandscape ? 22 : 26
        let street:   CGFloat = isLandscape ? 15 : 17

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primaryFixed)
                    .frame(width: tile, height: tile)
                Image(systemName: vm.currentInstruction.isEmpty
                      ? "arrow.up"
                      : maneuverIcon(for: vm.currentManeuver, instruction: vm.currentInstruction))
                    .font(.system(size: glyph, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }

            // No Spacer here on purpose: the icon is fixed-width, so the HStack hands ALL the
            // remaining width to this column, which is what lets the street name wrap instead of
            // truncating. A Spacer would compete for that same space and shrink it back.
            VStack(alignment: .leading, spacing: 2) {
                let distText = Self.turnDistanceText(vm.distanceToNextTurnMeters)
                if !distText.isEmpty {
                    Text(distText)
                        .font(.system(size: distance, weight: .black, design: .monospaced))
                        .foregroundColor(Color.primaryFixed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // Two lines now rather than one. At 17pt a long road name no longer fits on a
                // single line, and a truncated name is worth less than a wrapped one.
                Text(vm.currentInstruction.isEmpty ? "Follow route" : vm.currentInstruction)
                    .font(.system(size: street, weight: .semibold))
                    .foregroundColor(Color.onSurface)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: expand ? .infinity : nil, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primaryFixed.opacity(0.3), lineWidth: 1))
    }

    /// Distance-to-maneuver, rounded the way Google Maps rounds it.
    ///
    /// A raw `%.0f m` reported every metre, so the banner ticked through "347 m", "339 m",
    /// "331 m" — three digits of churn implying a precision GPS does not have, and nothing like
    /// the "350 m → 300 m → 250 m" cadence beside it on Google. Coarser as the number grows:
    /// 10 m steps up close where the rounding is a small share of the distance, 50 m out to a
    /// kilometre, tenths of a km beyond. Under 10 m the maneuver is happening, so it is named
    /// rather than measured.
    static func turnDistanceText(_ meters: Double) -> String {
        guard meters > 0 else { return "" }
        if meters < 10   { return "Now" }
        if meters < 500 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let toFifty = Int((meters / 50).rounded()) * 50
        if toFifty < 1000 { return "\(toFifty) m" }   // 975 m rounds to 1000, which belongs in km
        return String(format: "%.1f km", meters / 1000)
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
        case "ARRIVE":                         return "flag.checkered"
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

    /// Leaderboard row, with the live-rider count pinned to its trailing edge.
    ///
    /// The count sits OUTSIDE the scroll view on purpose: it is a fact about the convoy, not a
    /// rider card, so it must stay put while the cards scroll under it. It moved down here from
    /// the top row, which the turn banner now owns outright.
    private var leaderboardStrip: some View {
        HStack(spacing: 8) {
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
                    .padding(.leading, 20)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedRiderId) { _, id in
                    if let id {
                        withAnimation(.spring(response: 0.4)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            liveRiderCountPill
                .padding(.trailing, 20)
        }
    }

    /// Compact leaderboard for the landscape panel, with the live-rider count pinned trailing —
    /// same arrangement as portrait, and for the same reason: it moved out of the turn-banner row
    /// so that banner could have the panel's full width.
    private var landscapeLeaderboardStrip: some View {
        HStack(spacing: 6) {
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
            liveRiderCountPill
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
                value: vm.hasSpeedFix ? String(format: "%.0f", vm.mySpeedKmh) : "--",
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
                // sits next to regroup, on a phone being tapped at a set of lights. The same
                // confirmation now also carries Exit, since the back button is gone while
                // navigating.
                showEndConfirm = true
            } else {
                // Not the leader: they cannot end anything, so this is purely the exit and there
                // is nothing to confirm.
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
        // No rank number: the strip is already ordered by position, so printing it again spent
        // 18pt of a narrow pill on information the sequence carries. `row.rank` still drives the
        // leader highlight below.
        HStack(spacing: 7) {
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
