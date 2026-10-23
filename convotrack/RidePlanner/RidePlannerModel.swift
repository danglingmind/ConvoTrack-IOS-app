import SwiftUI
import CoreLocation
import Combine

// State behind the map-first ride planner (`design/CREATE_RIDE_REDESIGN.md`): the stops, the
// route through them, the alternatives Google offers, and the ride's own details. Create Ride
// and Edit Ride share it; saving and deleting stay in the two screens.

/// One stop on the ride. The first is the start and the last the destination; anything between
/// is a stop on the way. Keeping them in one list is what lets swap, reorder and remove treat
/// every row alike, the way Google Maps does.
struct PlannerStop: Identifiable, Equatable {
    let id = UUID()
    /// The chosen place. Nil while the rider is still searching for it, or for "Your location".
    var place: PlaceResult?
    /// Follows the rider's own position instead of a fixed place.
    var isCurrentLocation = false

    var isChosen: Bool { place != nil || isCurrentLocation }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.place == rhs.place && lhs.isCurrentLocation == rhs.isCurrentLocation
    }
}

/// What a stop is, from where it sits in the list.
enum PlannerStopRole {
    case start, stop, destination
}

@MainActor
final class RidePlannerModel: ObservableObject {

    /// Start and destination plus up to eight stops between them. The Routes API allows 25
    /// intermediates, but past this the stops card stops being readable over the map.
    static let maxStops = 10

    // MARK: Ride details

    @Published var title = ""
    @Published var maxRiders = 5
    /// Road types to keep off. Not stored with the ride: the route it produces is what's saved.
    @Published var avoid: RouteAvoidances = .none {
        didSet { if avoid != oldValue { recalculateRoute() } }
    }

    // MARK: Stops

    /// Always at least two: start first, destination last.
    @Published private(set) var stops: [PlannerStop] = [PlannerStop(isCurrentLocation: true), PlannerStop()]
    /// The rider's last known position, for "Your location" and the map's opening view.
    @Published private(set) var userLocation: CLLocation? = LocationService.shared.lastLocation

    // MARK: Route

    /// Alternatives for a direct start → destination route; empty once there are stops between.
    @Published private(set) var routes: [RouteOption] = []
    @Published private(set) var selectedRouteIndex = 0
    /// Where each alternative's time bubble sits, by index into `routes`.
    @Published private(set) var bubbleAnchors: [CLLocationCoordinate2D] = []
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var durationSeconds: TimeInterval = 0
    @Published private(set) var isRouting = false
    @Published private(set) var routeFailed = false
    @Published var cameraCommand: MapCameraCommand?

    /// The title we filled in from the destination. While the field still holds it, a new
    /// destination replaces it; once the rider types their own, it is theirs.
    private var suggestedTitle: String?
    private var routeTask: Task<Void, Never>?

    /// What was saved, for Edit Ride's "discard changes?" and its Save button. Nil when creating.
    private var savedSnapshot: Snapshot?
    /// The rider picked an alternative themselves. Tracked apart from the snapshot because a
    /// re-fetched route can differ from the saved one by a few metres without anyone touching it.
    @Published private(set) var riderPickedRoute = false

    private struct Snapshot: Equatable {
        let title: String
        let maxRiders: Int
        let stops: [String]
        let avoid: RouteAvoidances
    }

    private var snapshot: Snapshot {
        Snapshot(title: title.trimmingCharacters(in: .whitespaces), maxRiders: maxRiders,
                 stops: stops.map { $0.isCurrentLocation ? "me" : ($0.place?.id ?? "") },
                 avoid: avoid)
    }

    /// Edit Ride: something differs from what was saved.
    var hasChanges: Bool {
        guard let savedSnapshot else { return false }
        return riderPickedRoute || snapshot != savedSnapshot
    }

    init() {}

    /// Edit Ride: start from a saved ride's stops and route.
    init(ride: Ride) {
        title = ride.title
        maxRiders = ride.maxAllowedParticipants
        let saved = ride.waypoints.sorted { $0.order < $1.order }.map { wp in
            PlannerStop(place: PlaceResult(id: "wp_\(wp.order)", name: wp.name,
                                           coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                           formattedAddress: nil))
        }
        if saved.count >= 2 { stops = saved }
        if let stored = GoogleDirectionsService.decodedRoute(ride.routePolyline) {
            routeCoordinates = stored
            distanceMeters = ride.distanceMeters
            durationSeconds = TimeInterval(ride.estimatedDurationSeconds)
        }
        savedSnapshot = snapshot
    }

    // MARK: Derived

    func role(of stop: PlannerStop) -> PlannerStopRole {
        guard let i = stops.firstIndex(where: { $0.id == stop.id }) else { return .stop }
        return i == 0 ? .start : (i == stops.count - 1 ? .destination : .stop)
    }

    func coordinate(of stop: PlannerStop) -> CLLocationCoordinate2D? {
        stop.isCurrentLocation ? userLocation?.coordinate : stop.place?.coordinate
    }

    func name(of stop: PlannerStop) -> String {
        stop.isCurrentLocation ? String(localized: "Your location") : (stop.place?.name ?? "")
    }

    /// The planner leaves the empty map once the destination is chosen.
    var hasDestination: Bool { stops.last?.isChosen == true }

    /// The chosen stops, skipping a row whose search is still open.
    var chosenStops: [PlannerStop] { stops.filter(\.isChosen) }

    /// "Your location" is on the ride, but the phone hasn't said where that is.
    var isWaitingForLocation: Bool {
        userLocation == nil && chosenStops.contains(where: \.isCurrentLocation)
    }

    /// Coordinates of the chosen stops in riding order, or nil while one can't be placed.
    private var routeStopCoordinates: [CLLocationCoordinate2D]? {
        let coords = chosenStops.compactMap(coordinate(of:))
        return coords.count == chosenStops.count ? coords : nil
    }

    var canAddStop: Bool { stops.count < Self.maxStops }
    var canRemoveStops: Bool { stops.count > 2 }
    /// "Your location" can be offered for a row as long as no other row already uses it.
    func offersCurrentLocation(for id: UUID) -> Bool {
        !stops.contains { $0.isCurrentLocation && $0.id != id }
    }

    var hasRoute: Bool { !routeCoordinates.isEmpty && distanceMeters > 0 }

    func canCommit(isBusy: Bool) -> Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && stops.allSatisfy(\.isChosen)
            && routeStopCoordinates != nil
            && hasRoute
            && !isRouting
            && !isBusy
    }

    // MARK: Location

    /// Picks up the rider's position for the map and "Your location".
    func locateUser() {
        LocationService.shared.requestCurrentLocation { [weak self] location in
            Task { @MainActor in
                guard let self, let location else { return }
                let hadLocation = self.userLocation != nil
                self.userLocation = location
                guard !hadLocation else { return }
                if !self.hasDestination {
                    self.focusOnUser(animated: false)
                } else if self.stops.contains(where: \.isCurrentLocation) {
                    self.recalculateRoute()
                }
            }
        }
    }

    func focusOnUser(animated: Bool = true) {
        guard let c = userLocation?.coordinate else { return }
        cameraCommand = .focus(lat: c.latitude, lng: c.longitude, zoom: 13, animated: animated)
    }

    // MARK: Editing stops

    /// The empty destination row, for the search pill on the empty map.
    var destinationID: UUID { stops[stops.count - 1].id }

    func choose(_ place: PlaceResult, for id: UUID) {
        guard let i = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[i].place = place
        stops[i].isCurrentLocation = false
        if i == stops.count - 1 { RecentDestinations.remember(place) }
        stopsChanged()
    }

    func useCurrentLocation(for id: UUID) {
        guard let i = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[i].place = nil
        stops[i].isCurrentLocation = true
        locateUser()
        stopsChanged()
    }

    /// Adds an empty stop just before the destination, the usual place for a fuel or food stop,
    /// and returns it so its search can open. Reorder moves it anywhere else.
    func addStop() -> UUID? {
        guard canAddStop else { return nil }
        let stop = PlannerStop()
        stops.insert(stop, at: stops.count - 1)
        return stop.id
    }

    /// Drops a row the rider opened a search for and then backed out of.
    func discardIfEmpty(_ id: UUID) {
        guard let stop = stops.first(where: { $0.id == id }), !stop.isChosen, canRemoveStops else { return }
        stops.removeAll { $0.id == id }
    }

    func removeStop(_ id: UUID) {
        guard canRemoveStops else { return }
        stops.removeAll { $0.id == id }
        stopsChanged()
    }

    /// Start and destination trade places. Only offered for a two-stop ride; with stops between,
    /// reorder says what's wanted better than reversing the whole list.
    func swapEnds() {
        guard stops.count == 2 else { return }
        stops.reverse()
        stopsChanged()
    }

    /// Moves a stop one row up (-1) or down (+1). While a drag is in progress `reroute` is false
    /// and the route waits for `finishReorder`, so a drag across three rows asks Google once.
    func moveStop(_ id: UUID, by delta: Int, reroute: Bool = true) {
        guard let i = stops.firstIndex(where: { $0.id == id }) else { return }
        let target = i + delta
        guard stops.indices.contains(target) else { return }
        stops.swapAt(i, target)
        if reroute { stopsChanged() }
    }

    func finishReorder() { stopsChanged() }

    /// Back from the route preview: forget every stop but the start, keep the details.
    func clearDestination() {
        stops = [stops[0], PlannerStop()]
        recalculateRoute()
    }

    private func stopsChanged() {
        refreshSuggestedTitle()
        recalculateRoute()
    }

    private func refreshSuggestedTitle() {
        guard let place = stops.last?.place else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty || trimmed == suggestedTitle else { return }
        let suggestion = String(localized: "Ride to \(place.name)")
        title = suggestion
        suggestedTitle = suggestion
    }

    // MARK: Route calculation

    /// Re-routes through the current stops. A newer call cancels an older one still in flight,
    /// so a quick change of destination can't be overwritten by the route it replaced.
    func recalculateRoute(preferStoredMatch: Bool = false) {
        routeTask?.cancel()
        routeTask = Task { await computeRoute(preferStoredMatch: preferStoredMatch) }
    }

    private func computeRoute(preferStoredMatch: Bool) async {
        guard hasDestination, let coords = routeStopCoordinates, coords.count >= 2 else {
            applyNoRoute()
            if let d = stops.last.flatMap(coordinate(of:)) {
                cameraCommand = .focus(lat: d.latitude, lng: d.longitude, zoom: 13)
            } else if !hasDestination {
                focusOnUser()
            }
            return
        }

        let storedDistance = distanceMeters
        isRouting = true
        routeFailed = false
        defer { if !Task.isCancelled { isRouting = false } }

        // Direct start → destination: offer the alternatives. Google returns none once there are
        // intermediate stops.
        if coords.count == 2,
           let options = try? await GoogleDirectionsService.alternativeRoutes(from: coords[0], to: coords[1], avoiding: avoid) {
            guard !Task.isCancelled else { return }
            if options.count > 1 {
                routes = options
                bubbleAnchors = Self.bubbleAnchors(for: options.map(\.coordinates))
                applyRoute(preferStoredMatch ? Self.closestIndex(options, toDistance: storedDistance) : 0)
                fitCameraToRoute()
                return
            }
        }

        do {
            let result = try await GoogleDirectionsService.route(through: coords, avoiding: avoid)
            guard !Task.isCancelled else { return }
            routes = []
            bubbleAnchors = []
            selectedRouteIndex = 0
            routeCoordinates = result.coordinates
            distanceMeters = result.distanceMeters
            durationSeconds = result.durationSeconds
            fitCameraToRoute()
        } catch {
            guard !Task.isCancelled else { return }
            applyNoRoute()
            routeFailed = true
        }
    }

    private func applyNoRoute() {
        routes = []
        bubbleAnchors = []
        selectedRouteIndex = 0
        routeCoordinates = []
        distanceMeters = 0
        durationSeconds = 0
        isRouting = false
    }

    /// The rider picked the alternative at `index`. Selecting one doesn't move the camera: every
    /// alternative shares the same two ends, so the view already shows it.
    func selectRoute(_ index: Int) {
        guard routes.indices.contains(index), index != selectedRouteIndex else { return }
        riderPickedRoute = true
        applyRoute(index)
    }

    private func applyRoute(_ index: Int) {
        guard routes.indices.contains(index) else { return }
        selectedRouteIndex = index
        let option = routes[index]
        routeCoordinates = option.coordinates
        distanceMeters = option.distanceMeters
        durationSeconds = option.durationSeconds
    }

    /// Frames the route and every alternative. Map padding already keeps it clear of the top
    /// chrome and the sheet; the extra top inset leaves room for the destination pin, which is
    /// drawn above its coordinate and which `fit` knows nothing about.
    func fitCameraToRoute(animated: Bool = true) {
        let coords = routes.isEmpty ? routeCoordinates : routes.flatMap(\.coordinates)
        guard !coords.isEmpty else { return }
        cameraCommand = .fitRouteInsets(coords, top: GoogleMapView.stopPinTopExtent * 0.6,
                                        left: 40, bottom: 32, right: 40, animated: animated)
    }

    /// For each route, the point furthest from every other route: where it has split off on its
    /// own road, so its bubble points at a line no other route shares. The first and last tenth
    /// are skipped, since every alternative leaves from and arrives at the same place.
    ///
    /// Works on an even sample of each polyline (HIGH_QUALITY routes run to thousands of points),
    /// with distances in a flat projection, which is plenty to rank points a few km apart.
    static func bubbleAnchors(for routes: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
        func sample(_ coords: [CLLocationCoordinate2D], count: Int) -> [CLLocationCoordinate2D] {
            guard coords.count > count else { return coords }
            return (0..<count).map { coords[(coords.count - 1) * $0 / (count - 1)] }
        }
        let sampled = routes.map { sample($0, count: 120) }
        let lngScale = cos((sampled.first?.first?.latitude ?? 0) * .pi / 180)
        func distance2(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let dLat = a.latitude - b.latitude
            let dLng = (a.longitude - b.longitude) * lngScale
            return dLat * dLat + dLng * dLng
        }

        return sampled.indices.map { i in
            let points = sampled[i]
            guard !points.isEmpty else { return CLLocationCoordinate2D() }
            let others = sampled.indices.filter { $0 != i }.flatMap { sampled[$0] }
            let candidates = points.count >= 10 ? Array(points[(points.count / 10)...(points.count * 9 / 10)]) : points
            var best = points[points.count / 2]
            var bestDistance = -1.0
            for p in candidates {
                let nearest = others.lazy.map { distance2(p, $0) }.min() ?? 0
                if nearest > bestDistance {
                    bestDistance = nearest
                    best = p
                }
            }
            return best
        }
    }

    /// Edit Ride: the alternative closest to the saved distance, so the leader's earlier pick
    /// stays selected.
    private static func closestIndex(_ options: [RouteOption], toDistance target: Double) -> Int {
        guard target > 0 else { return 0 }
        return options.indices.min { abs(options[$0].distanceMeters - target) < abs(options[$1].distanceMeters - target) } ?? 0
    }

    // MARK: Saving

    /// Waypoints in the order the API expects: START → WAYPOINT* → DESTINATION. "Your location"
    /// is first given a real name, since every rider in the ride sees it and to them it would
    /// mean their own.
    func resolvedWaypoints() async -> [CreateWaypoint]? {
        let chosen = chosenStops
        guard chosen.count >= 2, chosen.count == stops.count else { return nil }
        var waypoints: [CreateWaypoint] = []
        for (i, stop) in chosen.enumerated() {
            guard let coord = coordinate(of: stop) else { return nil }
            var name = stop.place?.name ?? ""
            if stop.isCurrentLocation {
                name = await GooglePlacesService.reverseGeocode(coord)?.name ?? ""
            }
            if name.isEmpty { name = i == 0 ? String(localized: "Starting point") : String(localized: "Pinned location") }
            let type = i == 0 ? "START" : (i == chosen.count - 1 ? "DESTINATION" : "WAYPOINT")
            waypoints.append(CreateWaypoint(order: i, name: name, type: type,
                                            lat: coord.latitude, lng: coord.longitude))
        }
        return waypoints
    }
}
