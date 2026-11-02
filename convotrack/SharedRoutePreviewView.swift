import SwiftUI
import CoreLocation

/// A shared ride route opened from a link: the road that was ridden, the stops along it and the
/// leader's regroup stops. "Ride this route" hands it to the planner as a new ride the rider leads.
struct SharedRoutePreviewView: View {
    let token: String
    /// Called with the route and the leader stops the rider ticked.
    let onRide: (RouteClone) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Phase { case loading, loaded(SharedRoute), unavailable }
    @State private var phase: Phase = .loading
    @State private var chosenStops: Set<String> = []
    @State private var cameraCommand: MapCameraCommand?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DSScreenBackground()
            switch phase {
            case .loading:
                DSLoadingState()
            case .unavailable:
                DSErrorState(title: "This route isn't available",
                             message: "The link may have been turned off by the rider who shared it.") {
                    phase = .loading
                    Task { await load() }
                }
            case .loaded(let route):
                content(route)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .dsIcon(DS.IconSize.sm, weight: .bold)
                    .foregroundStyle(DS.Text.primary.base)
                    .frame(width: DS.Target.minimum, height: DS.Target.minimum)
                    .background(DS.Surface.raised.opacity(0.9), in: Circle())
            }
            .padding(DS.Space.p3)
            .accessibilityLabel(Text("Close"))
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: Content

    private func content(_ route: SharedRoute) -> some View {
        let ridden = GoogleDirectionsService.decodedRoute(route.actualRoutePolyline) ?? []
        let planned = GoogleDirectionsService.decodedRoute(route.plannedRoutePolyline) ?? []
        return VStack(spacing: 0) {
            GoogleMapView(
                routeCoords: ridden.isEmpty ? planned : ridden,
                // The plan stays visible, dimmed, so a detour reads as a detour.
                originalRouteCoords: ridden.isEmpty ? [] : planned,
                pins: pins(route),
                cameraCommand: cameraCommand,
                isInteractive: true
            )
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: DS.Space.p3) {
                if let by = route.sharedBy {
                    Text("Shared by \(by.firstName)").dsText(.eyebrow).foregroundStyle(DS.Accent.base)
                }
                Text(route.title).dsText(.heroTitle).lineLimit(2)
                Text(stats(route)).dsText(.body).foregroundStyle(DS.Text.secondary)

                if !route.leaderStops.isEmpty {
                    DSSectionHeading("Add the leader's stops")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.p2) {
                            ForEach(route.leaderStops) { stop in stopChip(stop) }
                        }
                    }
                }

                DSPrimaryButton(title: "Ride this route", systemImage: "arrow.turn.up.right") {
                    Analytics.capture(.sharedRouteCloneStarted, ["added_stops": chosenStops.count])
                    onRide(RouteClone(token: token, route: route,
                                      stops: route.leaderStops.filter { chosenStops.contains($0.id) }))
                }
            }
            .padding(DS.Space.screenInset)
            .background(DS.Background.base)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func stopChip(_ stop: SharedRoute.Stop) -> some View {
        let on = chosenStops.contains(stop.id)
        return Button {
            if on { chosenStops.remove(stop.id) } else { chosenStops.insert(stop.id) }
        } label: {
            Label(DSRegroupKind.label(stop.type), systemImage: on ? "checkmark" : DSRegroupKind.icon(stop.type))
                .dsText(.body)
                .padding(.horizontal, DS.Space.p3)
                .padding(.vertical, DS.Space.p2)
                .foregroundStyle(on ? DS.Background.base : DSRegroupKind.color(stop.type))
                .background(on ? DSRegroupKind.color(stop.type) : DS.Surface.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pins(_ route: SharedRoute) -> [MapPin] {
        var pins: [MapPin] = []
        for wp in route.waypoints {
            let c = CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng)
            pins.append(MapPin(id: "wp_\(wp.order)", coordinate: c,
                               style: wp.type == "DESTINATION" ? .destination(name: wp.name) : .waypoint(name: wp.name)))
        }
        for stop in route.leaderStops {
            pins.append(MapPin(id: "stop_\(stop.id)",
                               coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng),
                               style: .regroup(type: stop.type, caller: "")))
        }
        return pins
    }

    private func stats(_ route: SharedRoute) -> String {
        var parts = [String(format: "%.0f km", route.distanceMeters / 1000)]
        if let seconds = route.durationSeconds { parts.append(RideDuration.inline(seconds)) }
        if !route.leaderStops.isEmpty { parts.append(String(localized: "\(route.leaderStops.count) regroup stops")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Loading

    private func load() async {
        guard let route = try? await APIClient.shared.getSharedRoute(token) else { phase = .unavailable; return }
        Analytics.capture(.sharedRouteOpened)
        let ridden = GoogleDirectionsService.decodedRoute(route.actualRoutePolyline) ?? []
        let planned = GoogleDirectionsService.decodedRoute(route.plannedRoutePolyline) ?? []
        let stops = route.leaderStops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let coords = (ridden.isEmpty ? planned : ridden) + stops
        if !coords.isEmpty {
            // Top inset leaves the close button clear; bottom the sheet-like panel.
            cameraCommand = MapCameraCommand.fitRoute(coords, padding: 48)
        }
        phase = .loaded(route)
    }
}
