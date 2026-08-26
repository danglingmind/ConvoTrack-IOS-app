import SwiftUI
import GoogleMaps
import CoreLocation

// MARK: - Pin model

struct MapPin: Identifiable {
    enum Style {
        case userLocation(heading: Double)
        case destination(name: String)
        case waypoint(name: String)
        case lobbyStart
        case rider(name: String, avatarUrl: String?, isMe: Bool, rank: Int, isSelected: Bool, isOffline: Bool)
        case regroup(type: String)
        case emergency
        case simpleDot(color: UIColor, size: CGFloat)
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let style: Style
    var anchorBottom: Bool = true   // false → center anchor (simpleDot)
    var distanceText: String? = nil // shown under rider markers (distance from me)

    var styleHash: Int {
        var h = Hasher()
        switch style {
        // Heading is deliberately NOT part of the hash. The chevron bitmap is now
        // heading-independent — rotation is applied by the map via `GMSMarker.rotation` — so
        // including it re-baked a fresh bitmap on every GPS fix for an identical image.
        case .userLocation:
            h.combine(0)
        case .destination(let n):
            h.combine(1); h.combine(n)
        case .waypoint(let n):
            h.combine(2); h.combine(n)
        case .lobbyStart:
            h.combine(3)
        case .rider(let n, _, let me, let rank, let sel, let off):
            h.combine(4); h.combine(n); h.combine(me); h.combine(rank); h.combine(sel); h.combine(off)
        case .regroup(let t):
            h.combine(5); h.combine(t)
        case .simpleDot(_, let sz):
            h.combine(6); h.combine(Int(sz))
        case .emergency:
            h.combine(7)
        }
        h.combine(distanceText)   // re-bake when the displayed distance changes
        return h.finalize()
    }
}

// MARK: - Camera command

struct MapCameraCommand {
    let id: UUID
    /// Where the target sits in the viewport.
    ///
    /// This used to be inferred from `tilt > 0`, which silently coupled two unrelated things: flatten
    /// the camera to 2D and the marker would jump back to dead centre, losing the road ahead. It is
    /// now stated by the caller, so guidance keeps its low marker at any tilt.
    enum Framing {
        /// Guidance — target sits low, most of the viewport showing the road ahead.
        case roadAhead
        /// Looking at a place — target centred.
        case centered
    }

    enum Action {
        case fitCoords([CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool)
        case navigate(lat: Double, lng: Double, zoom: Float, bearing: Double, tilt: Double,
                      animated: Bool, framing: Framing)
    }
    let action: Action

    static func fitRoute(_ coords: [CLLocationCoordinate2D], padding: CGFloat = 48, animated: Bool = false) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .fitCoords(coords, padding: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding), animated: animated))
    }

    static func fitRouteInsets(_ coords: [CLLocationCoordinate2D], top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .fitCoords(coords, padding: UIEdgeInsets(top: top, left: left, bottom: bottom, right: right), animated: animated))
    }

    static func follow(lat: Double, lng: Double, speed: Double, bearing: Double, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .navigate(lat: lat, lng: lng, zoom: navZoom(forSpeedKmh: speed), bearing: bearing, tilt: navTilt, animated: animated, framing: .roadAhead))
    }

    /// Speed → zoom curve for the guidance camera, matched against Google Maps' navigation
    /// view: ~18.4 stopped or crawling through a junction, easing out to ~16.4 at highway
    /// speed, so the look-ahead stays roughly constant in *seconds of travel* rather than in
    /// metres. The three-bucket table this replaces sat about a full zoom level wider at city
    /// speed — twice the ground area Google shows.
    ///
    /// Interpolated rather than bucketed: bucketing makes the map visibly jump a whole level
    /// as you cross 20 or 60 km/h. Quantized to 0.25 so noisy GPS speed can't make it breathe.
    ///
    /// SCOPE — this is the zoom and nothing else. Camera pitch (`RideNavigationView.navTilt`,
    /// 52°) and where the marker sits in the viewport (the padding fraction in `applyCamera`,
    /// 0.35) are deliberately left alone. Changing those alongside the zoom compounds: a
    /// tighter zoom on a shallower pitch with the puck lower pushed the convoy markers, the
    /// destination pin and the road ahead off-screen. Tune this table on its own.
    private static let zoomAnchors: [(kmh: Double, zoom: Float)] = [
        (0, 18.4), (20, 18.1), (40, 17.6), (60, 17.2), (80, 16.9), (100, 16.6), (120, 16.4)
    ]

    static func navZoom(forSpeedKmh kmh: Double) -> Float {
        let s = max(0, kmh)
        var zoom = zoomAnchors[zoomAnchors.count - 1].zoom
        if let i = zoomAnchors.firstIndex(where: { s <= $0.kmh }) {
            if i == 0 {
                zoom = zoomAnchors[0].zoom
            } else {
                let lo = zoomAnchors[i - 1], hi = zoomAnchors[i]
                let t = Float((s - lo.kmh) / (hi.kmh - lo.kmh))
                zoom = lo.zoom + (hi.zoom - lo.zoom) * t
            }
        }
        return (zoom * 4).rounded() / 4
    }

    static func focus(lat: Double, lng: Double, zoom: Float = 15, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .navigate(lat: lat, lng: lng, zoom: zoom, bearing: 0, tilt: 0, animated: animated, framing: .centered))
    }

    /// Camera pitch for guidance — back to the original 52°.
    ///
    /// The pitch was never the problem: what read as "3D" was the SDK's extruded building layer
    /// (`isBuildingsEnabled`, on by default), which is now off. Tilt over a flat map is what Google
    /// Maps itself uses — perspective on the road ahead, no blocks stacked over the route.
    ///
    /// Restoring it is safe now that `Framing` is explicit: the marker's lower-third placement no
    /// longer rides on `tilt > 0`, so pitch and framing can change independently.
    static let navTilt: Double = 52
}

// MARK: - View

struct GoogleMapView: UIViewRepresentable {
    var routeCoords: [CLLocationCoordinate2D] = []         // active route — bright lime
    var originalRouteCoords: [CLLocationCoordinate2D] = [] // full planned route — dim
    /// Ordered stop markers (start → waypoints → destination).
    /// Used to draw end-caps and curved dotted connectors to polyline endpoints.
    var stopCoords: [CLLocationCoordinate2D] = []
    var pins: [MapPin] = []
    var cameraCommand: MapCameraCommand? = nil
    var isInteractive: Bool = true
    /// True while turn-by-turn guidance is running, i.e. `routeCoords` is being re-cut every GPS
    /// fix to start under the rider. The head of the active route is then the rider's own marker,
    /// not a route endpoint, so it gets no end cap of its own — see `applyRouteDecorations`.
    var isNavigating: Bool = false
    var onInteraction: (() -> Void)? = nil
    /// All alternative routes (index == position). The one at `selectedRouteIndex`
    /// is drawn bright via `routeCoords`; the rest render dim + tappable.
    var alternativeRoutes: [[CLLocationCoordinate2D]] = []
    var selectedRouteIndex: Int = 0
    var onSelectRoute: ((Int) -> Void)? = nil
    /// Screen geometry for riders currently off-screen (for edge indicators).
    /// Recomputed as the camera moves and when pins update.
    var onEdgeIndicators: (([EdgeIndicator]) -> Void)? = nil
    /// Where the app's top chrome ends, in map coordinates (the map's top edge is screen y=0, so
    /// this is just its bottom edge on screen). Edge indicators clamp below it instead of sliding
    /// up behind the turn-by-turn banner and leaderboard. 0 leaves the default margin in place.
    var topOverlayHeight: CGFloat = 0

    /// Height of the tallest stop-pin art drawn ABOVE its coordinate. Stop pins are
    /// bottom-anchored, so this is simply the tallest baked image: `DestinationPin` measures
    /// 70pt with a single-line name and 80pt once the name wraps to a second line
    /// (`LobbyStartPin` 57pt), plus ~12pt of headroom.
    ///
    /// The 80 this replaces was set when a wrapped name still baked to 70pt — because the
    /// second line was being clipped off (see `renderSwiftUIFit`). With that fixed the art is
    /// genuinely 80pt tall, so the old value left exactly zero margin and a destination at the
    /// top of a fitted route grazed the viewport edge.
    ///
    /// A camera fit must add this to its top inset: `GMSCameraUpdate.fit` frames the
    /// coordinates and knows nothing about the marker towering over them, so a route whose
    /// northernmost point is a stop would otherwise have that pin clipped off-screen.
    static let stopPinTopExtent: CGFloat = 92

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero, camera: GMSCameraPosition(latitude: 0, longitude: 0, zoom: 2))
        applyDarkStyle(to: mapView)
        mapView.isMyLocationEnabled = false
        mapView.isTrafficEnabled    = true
        // Defaults to true, which is what drew the extruded blue blocks over the route. Google's
        // own navigation view renders a flat map — buildings as footprints at most — so the road
        // geometry stays the loudest thing on screen. Off here, flat everywhere.
        mapView.isBuildingsEnabled  = false
        mapView.isIndoorEnabled     = false
        mapView.settings.compassButton  = false
        mapView.settings.myLocationButton = false
        mapView.settings.rotateGestures  = true
        mapView.settings.tiltGestures    = false
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let c = context.coordinator
        c.onInteraction = onInteraction
        c.onSelectRoute = onSelectRoute
        c.onEdgeIndicators = onEdgeIndicators
        c.topOverlayHeight = topOverlayHeight
        mapView.isUserInteractionEnabled = isInteractive

        // Dim, tappable alternatives sit below the bright selected route.
        c.applyAlternatives(alternativeRoutes, selectedIndex: selectedRouteIndex, to: mapView)
        c.applyRoute(originalRouteCoords, to: mapView, key: &c.originalRouteVersion, line: &c.originalRouteLine, color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 0.28), width: 3, dashed: false, zIndex: 98)
        c.applyRoute(routeCoords,         to: mapView, key: &c.casingVersion,        line: &c.casingLine,        color: UIColor(red: 0.353, green: 0.424, blue: 0, alpha: 1),    width: Coordinator.casingWidth,    dashed: false, zIndex: 99)
        c.applyRoute(routeCoords,         to: mapView, key: &c.routeVersion,         line: &c.routeLine,         color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1),    width: Coordinator.routeFaceWidth, dashed: false, zIndex: 100)
        c.applyRouteDecorations(routeCoords: routeCoords, originalCoords: originalRouteCoords, stopCoords: stopCoords, isNavigating: isNavigating, to: mapView)
        c.applyPins(pins, to: mapView)

        if let cmd = cameraCommand, cmd.id != c.lastCameraId {
            c.lastCameraId = cmd.id
            c.applyCamera(cmd, to: mapView)
        }

        // Riders may have moved (applyPins updates positions) without a camera
        // change; refresh edge geometry off the update cycle to avoid mutating
        // SwiftUI state during a view update.
        if onEdgeIndicators != nil {
            DispatchQueue.main.async { [weak mapView] in
                guard let mapView else { return }
                c.computeEdgeIndicators(mapView)
            }
        }
    }

    // MARK: - Dark style

    private func applyDarkStyle(to mapView: GMSMapView) {
        let json = """
        [{"elementType":"geometry","stylers":[{"color":"#131313"}]},
         {"elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},
         {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a1a"}]},
         {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2c2c2c"}]},
         {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#333333"}]},
         {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},
         {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#555555"}]},
         {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050505"}]},
         {"featureType":"poi","stylers":[{"visibility":"off"}]},
         {"featureType":"transit","stylers":[{"visibility":"off"}]}]
        """
        if let style = try? GMSMapStyle(jsonString: json) {
            mapView.mapStyle = style
        }
    }
}

// MARK: - Coordinator

extension GoogleMapView {

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onInteraction: (() -> Void)?
        var onSelectRoute: ((Int) -> Void)?
        var onEdgeIndicators: (([EdgeIndicator]) -> Void)?
        var topOverlayHeight: CGFloat = 0
        private var lastEmittedIndicators: [EdgeIndicator] = []
        /// Edge-indicator recomputes are throttled because they sit in a self-sustaining loop:
        /// `didChange` fires once per frame of every camera animation → compute → emit → SwiftUI
        /// re-renders the navigation screen (rebuilding pins, re-baking marker images) →
        /// `updateUIView` → schedules another compute. `lastEmittedIndicators` is a weak brake,
        /// since `edgePoint` moves with any camera nudge, so the equality check almost never
        /// holds. Left unbounded the loop runs as fast as the main queue allows, and anything
        /// else demanding the main thread at the same time (a keyboard presenting over the map,
        /// for instance) is competing with it.
        private static let minIndicatorInterval: TimeInterval = 0.1   // 10 Hz, matching the camera tick cap

        /// Only a coordinate that means "no fix" is dropped — not one that is merely far away.
        ///
        /// A distance ceiling was tried here and was the wrong signal: it suppressed a rider on a
        /// simulated location (a phone in Bangalore vs the iOS Simulator's Apple Park default is
        /// 14,058 km), which silently removed every indicator on a two-device test rig. Distance
        /// cannot distinguish "wrong" from "far" — but (0,0) is never a real rider, it is the
        /// zero value of a coordinate that was never set.
        private static func isUnsetCoordinate(_ c: CLLocationCoordinate2D) -> Bool {
            !CLLocationCoordinate2DIsValid(c) || (abs(c.latitude) < 0.0001 && abs(c.longitude) < 0.0001)
        }
        private var lastIndicatorComputeDate: Date = .distantPast
        private var hasPendingIndicatorPass = false

        var routeLine:         GMSPolyline? = nil
        var originalRouteLine: GMSPolyline? = nil
        var casingLine:        GMSPolyline? = nil   // dark-lime sidewall under routeLine (3D extrude)
        var routeVersion         = 0
        var originalRouteVersion = 0
        var casingVersion        = 0

        // Route thickness. `routeChunkiness` is the single dial; the casing (3D
        // sidewall) derives from it via `casingRatio` so the extrude looks
        // consistent at any width.
        static let routeChunkiness: CGFloat = 8
        static let casingRatio:     CGFloat = 13.0 / 8.0
        static var routeFaceWidth:  CGFloat { routeChunkiness }
        static var casingWidth:     CGFloat { routeChunkiness * casingRatio }

        // Dim, tappable alternative routes (userData carries the global index)
        var altLines:   [GMSPolyline] = []
        var altVersion: Int = 0

        var markers:       [String: GMSMarker] = [:]
        var pinRenderKeys: [String: Int]        = [:]   // styleHash — gates icon re-bake
        var pinModels:     [String: MapPin]     = [:]   // last pin per id, to re-bake on avatar load

        // Avatar photos for rider markers. Baking a marker icon is synchronous, so each avatar
        // is fetched once, cached by URL, and the affected rider marker(s) re-baked when it lands.
        var avatarImages:   [String: UIImage] = [:]
        var avatarInFlight: Set<String>       = []

        /// Marker draw order (markers always render above polylines in GMS, so these only
        /// order markers among themselves):
        /// emergency → regroup → user → destination → waypoint → start → riders → dots.
        ///
        /// Stops outrank riders deliberately: they're the fixed landmarks the route is built
        /// from, and a rider avatar drifting over the destination flag hides the one marker
        /// that can't be inferred from anything else on screen. Destination/waypoint/start
        /// also get distinct values — they previously shared 30, leaving GMS to break the tie
        /// arbitrarily, so which pin won was undefined when two stops overlapped.
        static func zIndex(for style: MapPin.Style) -> Int32 {
            switch style {
            case .emergency:    return 100
            case .regroup:      return 90
            case .userLocation: return 80
            case .destination:  return 70
            case .waypoint:     return 65
            case .lobbyStart:   return 60
            case .rider:        return 40
            case .simpleDot:    return 10
            }
        }

        var lastCameraId: UUID? = nil

        // Route decorations — end-cap dots and curved dotted connectors
        var endCapMarkers:    [GMSMarker]   = []
        var connectorLines:   [GMSPolyline] = []
        var decorationVersion: Int = 0

        // MARK: Alternatives

        /// Draws every alternative except the selected one as a dim, tappable line.
        /// The selected route is drawn bright by `applyRoute(routeCoords:)`.
        func applyAlternatives(
            _ alts: [[CLLocationCoordinate2D]],
            selectedIndex: Int,
            to mapView: GMSMapView
        ) {
            let newVersion: Int = {
                var h = Hasher()
                h.combine(alts.count)
                h.combine(selectedIndex)
                for route in alts {
                    h.combine(route.count)
                    if let f = route.first { h.combine(f.latitude.bitPattern); h.combine(f.longitude.bitPattern) }
                    if let l = route.last  { h.combine(l.latitude.bitPattern); h.combine(l.longitude.bitPattern) }
                }
                return h.finalize()
            }()
            guard newVersion != altVersion else { return }
            altVersion = newVersion

            altLines.forEach { $0.map = nil }
            altLines = []
            guard alts.count > 1 else { return }   // nothing to choose between

            for (i, coords) in alts.enumerated() where i != selectedIndex && !coords.isEmpty {
                let path = GMSMutablePath()
                coords.forEach { path.add($0) }
                let line = GMSPolyline(path: path)
                line.strokeWidth = 4
                line.strokeColor = UIColor(white: 0.78, alpha: 0.42)
                line.geodesic    = false
                line.zIndex      = 97   // below selected (100) and original (98)
                line.isTappable  = true
                line.userData    = i
                line.map         = mapView
                altLines.append(line)
            }
        }

        // MARK: Route

        func applyRoute(
            _ coords: [CLLocationCoordinate2D],
            to mapView: GMSMapView,
            key: inout Int,
            line: inout GMSPolyline?,
            color: UIColor,
            width: CGFloat,
            dashed: Bool,
            zIndex: Int32 = 0
        ) {
            // Hash count + first/last coords so two different routes with the same
            // coordinate count are not mistaken for the same polyline.
            let newVersion: Int = {
                guard !coords.isEmpty else { return 0 }
                var h = Hasher()
                h.combine(coords.count)
                h.combine(coords.first!.latitude.bitPattern)
                h.combine(coords.first!.longitude.bitPattern)
                h.combine(coords.last!.latitude.bitPattern)
                h.combine(coords.last!.longitude.bitPattern)
                return h.finalize()
            }()
            guard newVersion != key else { return }
            key = newVersion

            guard !coords.isEmpty else {
                line?.map = nil
                line = nil
                return
            }

            let path = GMSMutablePath()
            coords.forEach { path.add($0) }

            // Reuse the existing overlay when one is already on the map: mutating
            // `.path` updates the geometry in place instead of destroying and
            // recreating the GMSPolyline every GPS tick. Color/width/dashed never
            // change across ticks for a given line, so only the path needs updating.
            if let existing = line {
                existing.path = path
                return
            }

            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = width
            polyline.strokeColor = color
            // geodesic=false: draw straight screen-space segments between the already
            // road-snapped coordinates. geodesic=true introduces great-circle deviation
            // which at lane scale can shift the stroke onto the adjacent lane.
            polyline.geodesic = false
            polyline.zIndex   = zIndex

            if dashed {
                let solidSpan = GMSStyleSpan(style: GMSStrokeStyle.solidColor(color), segments: 3)
                let gapSpan   = GMSStyleSpan(style: GMSStrokeStyle.solidColor(.clear), segments: 2)
                polyline.spans = [solidSpan, gapSpan]
            }

            polyline.map = mapView
            line = polyline
        }

        // MARK: Route decorations

        func applyRouteDecorations(
            routeCoords: [CLLocationCoordinate2D],
            originalCoords: [CLLocationCoordinate2D],
            stopCoords: [CLLocationCoordinate2D],
            isNavigating: Bool,
            to mapView: GMSMapView
        ) {
            // Version hash over all endpoints so we redraw only on actual changes.
            //
            // The active route's FIRST point is excluded while navigating, for two reasons: it is
            // no longer drawn (see below), and it moves with every GPS fix — so including it made
            // this version miss once a second and tear down and rebuild four rendered marker
            // images plus two 24-point bezier connectors on the main thread, once a second, to
            // arrive at the same picture.
            let newVersion: Int = {
                var h = Hasher()
                let endpoints = [isNavigating ? nil : routeCoords.first, routeCoords.last,
                                 originalCoords.first, originalCoords.last,
                                 stopCoords.first, stopCoords.last]
                for coord in endpoints.compactMap({ $0 }) {
                    h.combine(coord.latitude.bitPattern)
                    h.combine(coord.longitude.bitPattern)
                }
                h.combine(stopCoords.count)
                h.combine(isNavigating)
                return h.finalize()
            }()
            guard newVersion != decorationVersion else { return }
            decorationVersion = newVersion

            // Clear previous decorations
            endCapMarkers.forEach { $0.map = nil }
            endCapMarkers = []
            connectorLines.forEach { $0.map = nil }
            connectorLines = []

            // End caps render BELOW stop pins (zIndex 2) so the pin icon sits on top
            // and the circle peeks out as a visible halo around the pin base.
            // Stop pins are 60–70, set in applyPins via `zIndex(for:)`.

            // End caps on original planned route (dim)
            if let first = originalCoords.first {
                endCapMarkers.append(endCapMarker(at: first, size: 14, opacity: 0.45, zIndex: 2, to: mapView))
            }
            if let last = originalCoords.last {
                endCapMarkers.append(endCapMarker(at: last,  size: 14, opacity: 0.45, zIndex: 2, to: mapView))
            }

            // End caps on the active route (bright).
            //
            // The head cap is suppressed while navigating. It used to be drawn deliberately,
            // because the route start (road-projected) sat apart from the GPS-position user pin —
            // but that gap was the bug, not a feature to label: it put a second lime dot on the
            // map a few metres off the chevron, tracking the polyline rather than the rider, which
            // read as the route's start point and the marker sliding along at different paces.
            // The route now starts underneath the chevron (`trimActiveRoute`), so the chevron IS
            // the head marker and a cap here would only double-draw it.
            if let first = routeCoords.first, !isNavigating {
                endCapMarkers.append(endCapMarker(at: first, size: 16, opacity: 1.0, zIndex: 2, to: mapView))
            }
            if let last = routeCoords.last {
                endCapMarkers.append(endCapMarker(at: last,  size: 16, opacity: 1.0, zIndex: 2, to: mapView))
            }

            // Curved dotted connectors: first stop → first polyline point, last stop → last polyline point.
            // No distance threshold — addCurvedConnector's own `guard len > 0` handles the degenerate
            // case where the stop is exactly on the route endpoint.
            let baseCoords = originalCoords.isEmpty ? routeCoords : originalCoords
            if let stopFirst = stopCoords.first, let routeFirst = baseCoords.first {
                addCurvedConnector(from: stopFirst, to: routeFirst, to: mapView)
            }
            if let stopLast = stopCoords.last, let routeLast = baseCoords.last {
                addCurvedConnector(from: stopLast, to: routeLast, to: mapView)
            }
        }

        private func coordDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }

        private func endCapMarker(at coord: CLLocationCoordinate2D, size: CGFloat, opacity: CGFloat, zIndex: Int32, to mapView: GMSMapView) -> GMSMarker {
            let scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
            }())
            let image = renderer.image { ctx in
                let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: opacity)
                lime.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                UIColor.white.withAlphaComponent(opacity * 0.9).setStroke()
                ctx.cgContext.setLineWidth(1.5)
                ctx.cgContext.strokeEllipse(in: CGRect(x: 0.75, y: 0.75, width: size - 1.5, height: size - 1.5))
            }
            let marker = GMSMarker(position: coord)
            marker.icon         = image
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.zIndex       = zIndex
            marker.map          = mapView
            return marker
        }

        private func addCurvedConnector(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, to mapView: GMSMapView) {
            // Flat-earth projection (degrees → approx equal-scale space)
            let cosLat = cos(a.latitude * .pi / 180)
            let ax = a.longitude * cosLat, ay = a.latitude
            let bx = b.longitude * cosLat, by = b.latitude
            let dx = bx - ax, dy = by - ay
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0 else { return }

            // Perpendicular unit vector (rotated 90° CW for a consistent arc direction)
            let px = dy / len, py = -dx / len

            // Control point: midpoint + 30% distance in perpendicular direction
            let offset = len * 0.30
            let cpx = (ax + bx) / 2 + px * offset
            let cpy = (ay + by) / 2 + py * offset

            // Sample quadratic bezier at 24 points
            let path = GMSMutablePath()
            let steps = 24
            for i in 0...steps {
                let t  = Double(i) / Double(steps)
                let t1 = 1.0 - t
                let qx = t1 * t1 * ax + 2 * t1 * t * cpx + t * t * bx
                let qy = t1 * t1 * ay + 2 * t1 * t * cpy + t * t * by
                path.add(CLLocationCoordinate2D(latitude: qy, longitude: qx / cosLat))
            }

            let polyline         = GMSPolyline(path: path)
            polyline.strokeWidth = 2
            polyline.zIndex      = 96
            let limeConnector    = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 0.75)
            let solidSpan        = GMSStyleSpan(style: .solidColor(limeConnector), segments: 2)
            let gapSpan          = GMSStyleSpan(style: .solidColor(.clear),        segments: 2)
            polyline.spans       = [solidSpan, gapSpan]
            polyline.geodesic    = false
            polyline.map         = mapView
            connectorLines.append(polyline)
        }

        // MARK: Pins

        func applyPins(_ pins: [MapPin], to mapView: GMSMapView) {
            let currentIds = Set(pins.map { $0.id })

            // Remove stale
            for id in Array(markers.keys) where !currentIds.contains(id) {
                markers[id]?.map = nil
                markers.removeValue(forKey: id)
                pinRenderKeys.removeValue(forKey: id)
                pinModels.removeValue(forKey: id)
            }

            for pin in pins {
                pinModels[pin.id] = pin
                let newKey = pin.styleHash

                if let marker = markers[pin.id] {
                    // Always update position (riders move) and heading (the rider turns)
                    marker.position = pin.coordinate
                    if let rotation = Self.groundRotation(for: pin.style) {
                        marker.rotation = rotation
                    }
                    // Re-render only when the style changed
                    if pinRenderKeys[pin.id] != newKey {
                        pinRenderKeys[pin.id] = newKey
                        let baked = renderMarker(pin)
                        marker.icon         = baked.image
                        marker.groundAnchor = baked.anchor
                        // Set here rather than every tick: `isFlat` only changes if a pin id
                        // changes style, which is exactly what a style-hash miss means. Assigning
                        // it on each location update would churn the marker for no change.
                        marker.isFlat       = Self.groundRotation(for: pin.style) != nil
                    }
                } else {
                    let baked = renderMarker(pin)
                    let marker = GMSMarker()
                    marker.position     = pin.coordinate
                    marker.groundAnchor = baked.anchor
                    marker.icon         = baked.image
                    marker.zIndex       = Self.zIndex(for: pin.style)
                    if let rotation = Self.groundRotation(for: pin.style) {
                        // Flat = lies on the road plane and turns with the map, and `rotation` is
                        // then measured clockwise from NORTH rather than from screen-up. That is
                        // the whole fix: the map owns the conversion into screen space, so the
                        // chevron stays true whatever the camera bearing is doing. It also
                        // foreshortens under the navigation tilt, like Google's own puck.
                        marker.isFlat   = true
                        marker.rotation = rotation
                    }
                    marker.map          = mapView
                    markers[pin.id]     = marker
                    pinRenderKeys[pin.id] = newKey
                }
            }
        }

        /// Compass heading a marker should lie at on the ground, for the pin styles that carry
        /// one. Only the user chevron does; every other marker is a billboard that should stay
        /// upright on screen however the camera is rotated.
        private static func groundRotation(for style: MapPin.Style) -> CLLocationDirection? {
            if case .userLocation(let heading) = style { return heading }
            return nil
        }

        // MARK: Camera

        func applyCamera(_ cmd: MapCameraCommand, to mapView: GMSMapView) {
            switch cmd.action {
            case .fitCoords(let coords, let padding, let animated):
                guard !coords.isEmpty else { return }
                var bounds = GMSCoordinateBounds()
                coords.forEach { bounds = bounds.includingCoordinate($0) }
                let update = GMSCameraUpdate.fit(bounds, with: padding)
                if animated { mapView.animate(with: update) } else { mapView.moveCamera(update) }

            case .navigate(let lat, let lng, let zoom, let bearing, let tilt, let animated, let framing):
                // Top padding shifts the camera target down, so the marker sits low and the
                // viewport is mostly road ahead. Driven by `framing`, not by tilt — a flat 2D
                // guidance camera needs this just as much as a pitched one.
                if case .roadAhead = framing, mapView.bounds.height > 0 {
                    mapView.padding = UIEdgeInsets(top: mapView.bounds.height * 0.35, left: 0, bottom: 0, right: 0)
                } else {
                    mapView.padding = .zero
                }
                let pos = GMSCameraPosition(latitude: lat, longitude: lng, zoom: zoom, bearing: bearing, viewingAngle: tilt)
                if animated { mapView.animate(to: pos) } else { mapView.camera = pos }
            }
        }

        // MARK: Icon rendering

        /// Body art for a pin plus the point within it that is the semantic tip
        /// (the pixel that must sit on the true coordinate).
        ///
        /// No canvas padding is needed here: the stop pins carry no `.shadow`, so their layout
        /// bounds are their full visual extent and `ImageRenderer` can't clip anything. Adding
        /// a shadow back to one of these views WOULD clip — shadows don't contribute to layout,
        /// so the canvas stays flush with the art and the halo is sliced off at the edge.
        private func renderBody(_ pin: MapPin) -> (image: UIImage, anchorInBody: CGPoint)? {
            switch pin.style {
            case .destination(let name):
                guard let img = renderSwiftUIFit(DestinationPin(name: name)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height))
            case .waypoint(let name):
                guard let img = renderSwiftUIFit(WaypointPin(name: name)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height))
            case .lobbyStart:
                guard let img = renderSwiftUIFit(LobbyStartPin()) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height))
            // Intrinsic size, like the stop pins: baking these into a fixed 70×90 canvas
            // centred their ~62pt art, leaving ~14pt of empty canvas below it — so with a
            // bottom anchor the marker floated that far above its true coordinate.
            case .regroup(let type):
                guard let img = renderSwiftUIFit(RegroupPin(type: type)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height))
            case .emergency:
                guard let img = renderSwiftUIFit(EmergencyPin()) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height))
            case .rider(let name, let avatarUrl, let isMe, _, let isSelected, let isOffline):
                let size = Self.riderCircleSize(isSelected)
                // Cached photo if we have it; nil triggers an async fetch + re-bake and draws the
                // letter fallback in the meantime.
                let avatar = avatarImage(for: avatarUrl)
                guard let img = renderRiderIcon(name: name, avatar: avatar, isMe: isMe, isSelected: isSelected, isOffline: isOffline, distanceText: pin.distanceText) else { return nil }
                // Anchor at the circle's center (name band sits above it, distance below).
                return (img, CGPoint(x: img.size.width / 2, y: Self.riderNameBandH + size / 2))
            default:
                return nil
            }
        }

        /// Renders a marker icon and the normalized ground anchor (the point that
        /// sits on the coordinate). No collision offsets — pins draw at their true
        /// position and simply overlap when close.
        func renderMarker(_ pin: MapPin) -> (image: UIImage?, anchor: CGPoint) {
            switch pin.style {
            case .userLocation:
                return (renderUserLocationIcon(), CGPoint(x: 0.5, y: 0.5))
            case .simpleDot(let c, let s):
                return (renderDotIcon(color: c, size: s), CGPoint(x: 0.5, y: 0.5))
            // .lobbyStart is handled by renderBody: baking it into a fixed 70×80 canvas
            // centred its ~61pt art, leaving the tip ~10pt above the image's bottom edge —
            // so with a bottom anchor the whole pin floated above its true coordinate.
            default:
                guard let body = renderBody(pin) else { return (nil, CGPoint(x: 0.5, y: 1.0)) }
                // groundAnchor at the body's semantic tip, normalized to the image.
                let anchor = CGPoint(x: body.anchorInBody.x / body.image.size.width,
                                     y: body.anchorInBody.y / body.image.size.height)
                return (body.image, anchor)
            }
        }

        /// Renders a pin at its intrinsic size, so labels that wrap to a second line are not
        /// clipped. The view itself caps its label width (via `.frame(maxWidth:)`), which
        /// bounds the marker's footprint so a long name can't sprawl across the screen even
        /// when the pin sits at a corner. The pin content is horizontally centered, so the
        /// bottom-center ground anchor sits the marker's base on its coordinate.
        ///
        /// Every pin goes through this. The fixed-canvas variant that used to live here was
        /// removed: `.frame(width:height:)` centres art smaller than the canvas, so the
        /// leftover space below it pushed the marker off its coordinate by half the slack.
        ///
        /// Two passes, because one is provably wrong for any name that wraps. `ImageRenderer`
        /// sizes its canvas by proposing `.unspecified`, and under that proposal a `Text`
        /// reports its SINGLE-LINE ideal height — while the label's `.frame(maxWidth:)` clamps
        /// the width regardless, so the text then lays out over two lines inside a canvas
        /// measured for one. The overflow doesn't spill harmlessly: SwiftUI compresses the
        /// stack to fit, which sliced the bottom off the name card AND squeezed the pin head
        /// above it — a 44pt destination circle baked at ~41pt, flattened and cropped along its
        /// top edge. (Measured: "Kempegowda International Airport Bengaluru" baked to 128×70pt
        /// with 46pt of head art; the same pin two-passed bakes to 128×80pt with the full 49pt.)
        ///
        /// Pass 1 resolves the width, which is already correct — `maxWidth` clamps under any
        /// proposal. Pass 2 re-proposes that now-definite width so the label's ideal height is
        /// measured against the wrap that will actually happen. Names short enough to fit on one
        /// line are untouched: their pass-1 width is their natural width, so pass 2 is a no-op
        /// and the card still shrinks to fit rather than padding out to `maxWidth`.
        private func renderSwiftUIFit<V: View>(_ view: V) -> UIImage? {
            let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
            renderer.scale = UIScreen.main.scale
            guard let natural = renderer.uiImage else { return nil }
            renderer.proposedSize = ProposedViewSize(width: natural.size.width, height: nil)
            return renderer.uiImage ?? natural
        }

        // MARK: User location chevron

        /// Chevron footprint (pointing up, before rotation) — the one dial for how
        /// big the user marker draws. Google's navigation puck is a touch taller
        /// than it is wide; the corner radii and canvas derive from this, so the
        /// shape stays proportional at any size.
        static let userChevronSize = CGSize(width: 34, height: 38)

        /// White keyline width, scaled off the chevron so it stays proportional.
        private static var userChevronStroke: CGFloat { userChevronSize.height * 0.075 }

        /// Google Maps' navigation chevron: a rounded arrowhead whose tail is
        /// notched inward, so the silhouette reads as direction rather than as a
        /// plain triangle. Built as a rounded polygon around four points — tip,
        /// two tail corners, and the tail notch — centered on the origin and
        /// pointing along -y.
        private static func userChevronPath(size: CGSize) -> CGPath {
            let w = size.width, h = size.height
            let tip   = CGPoint(x: 0,      y: -h / 2)
            let right = CGPoint(x:  w / 2, y:  h / 2)
            let notch = CGPoint(x: 0,      y:  h / 2 - h * 0.27)   // tail cut-in
            let left  = CGPoint(x: -w / 2, y:  h / 2)

            // Radii as fractions of height so scaling the chevron doesn't change
            // how rounded it reads.
            let tipR = h * 0.096, tailR = h * 0.119, notchR = h * 0.111

            let path = CGMutablePath()
            // Start mid-edge (tip → right) so the first corner arc has an incoming
            // edge to round against; closeSubpath rejoins along that same edge.
            path.move(to: CGPoint(x: (tip.x + right.x) / 2, y: (tip.y + right.y) / 2))
            path.addArc(tangent1End: right, tangent2End: notch, radius: tailR)
            path.addArc(tangent1End: notch, tangent2End: left,  radius: notchR)
            path.addArc(tangent1End: left,  tangent2End: tip,   radius: tailR)
            path.addArc(tangent1End: tip,   tangent2End: right, radius: tipR)
            path.closeSubpath()
            return path
        }

        /// The chevron in our lime, with Google's white keyline and drop shadow, drawn pointing
        /// due north. Heading is NOT baked in.
        ///
        /// It used to be, and that was the bug: the icon was rotated by the absolute heading,
        /// which is only right on a north-up map — but during navigation the camera is set to
        /// `bearing: userHeading`, so the map is heading-up and the direction of travel already
        /// points to the top of the screen. A `GMSMarker` is a billboard by default (`isFlat`
        /// false), so the icon never counter-rotated with the map and the rotation was applied
        /// once and never undone. The on-screen error equalled the camera bearing: correct
        /// heading north, 90° off heading east, and exactly backwards heading south.
        ///
        /// The marker is now flat with `rotation` set to the heading (see `applyPins`), so the
        /// map itself converts north-relative rotation into screen space — correct at any camera
        /// bearing, mid-animation, and while free-looking. This also makes the bitmap constant,
        /// so it is baked once instead of on every fix.
        private func renderUserLocationIcon() -> UIImage {
            // Square canvas centred on the chevron. The marker rotates about its ground anchor
            // (0.5, 0.5) — the canvas centre — so keeping it square and generous means the art
            // sits at the centre of rotation at every heading, exactly as before.
            let sz = Self.userChevronSize
            let reach = ((sz.width / 2) * (sz.width / 2) + (sz.height / 2) * (sz.height / 2)).squareRoot()
            let canvas = (reach * 2 + Self.userChevronStroke + 12).rounded(.up)
            let scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: {
                let f = UIGraphicsImageRendererFormat()
                f.scale = scale
                return f
            }())
            let path = Self.userChevronPath(size: Self.userChevronSize)
            let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)

            return renderer.image { ctx in
                let cg = ctx.cgContext
                cg.translateBy(x: canvas / 2, y: canvas / 2)

                // Fill, lifted off the map by the same soft shadow Google uses.
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4,
                             color: UIColor.black.withAlphaComponent(0.55).cgColor)
                cg.addPath(path)
                cg.setFillColor(lime.cgColor)
                cg.fillPath()
                cg.restoreGState()

                // White keyline — separates the marker from the lime route it rides on.
                cg.addPath(path)
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(Self.userChevronStroke)
                cg.setLineJoin(.round)
                cg.strokePath()
            }
        }

        private func renderDotIcon(color: UIColor, size: CGFloat) -> UIImage {
            let scale  = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
            }())
            return renderer.image { ctx in
                let r = CGRect(x: 0, y: 0, width: size, height: size)
                color.setFill()
                ctx.cgContext.fillEllipse(in: r)
                UIColor(white: 0.07, alpha: 1).setStroke()
                ctx.cgContext.setLineWidth(2)
                ctx.cgContext.strokeEllipse(in: r.insetBy(dx: 1, dy: 1))
            }
        }

        /// Height of the name band drawn above the rider circle. The circle's center
        /// (the marker's anchor) is therefore at `riderNameBandH + size/2`.
        static let riderNameBandH: CGFloat = 20

        /// Rider circle diameter. Kept small so a rider sitting on a sharp turn
        /// doesn't hide the route curve underneath. Shared by the renderer and the
        /// anchor math so the circle center stays exactly on the coordinate.
        static func riderCircleSize(_ isSelected: Bool) -> CGFloat { isSelected ? 40 : 32 }

        /// A rider marker: a bordered circle (avatar or initial) centered on the
        /// coordinate — no tip, no rank badge — with the name above and the distance
        /// from the current user below. Border uses the route lime.
        private func renderRiderIcon(name: String, avatar: UIImage?, isMe: Bool, isSelected: Bool, isOffline: Bool, distanceText: String?) -> UIImage? {
            let size = Self.riderCircleSize(isSelected)
            let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)

            // Name (above) — first name, uppercased.
            let name0 = (name.components(separatedBy: " ").first?.uppercased() ?? "") as NSString
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: isSelected ? 9 : 8, weight: .black),
                .foregroundColor: UIColor.white
            ]
            let ns = name0.size(withAttributes: nameAttrs)

            // Distance (below).
            let dist = (distanceText ?? "") as NSString
            let distAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: lime
            ]
            let ds = distanceText == nil ? .zero : dist.size(withAttributes: distAttrs)

            let nameBandH = Self.riderNameBandH
            let distBandH: CGFloat = distanceText == nil ? 0 : 16
            let canvasW = max(size + 8, ceil(ns.width) + 8, ceil(ds.width) + 8)
            let totalH  = nameBandH + size + distBandH
            let cx      = canvasW / 2
            let circleRect = CGRect(x: cx - size / 2, y: nameBandH, width: size, height: size)

            let scale  = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasW, height: totalH), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
            }())
            return renderer.image { ctx in
                let cg = ctx.cgContext
                // Dim the entire marker for a rider who's gone offline — mirrors the greyed
                // leaderboard row so the map and list agree on who's present.
                if isOffline { cg.setAlpha(0.5) }

                if let avatar {
                    // Aspect-fill the photo into the circle.
                    cg.saveGState()
                    cg.addEllipse(in: circleRect); cg.clip()
                    let s = max(size / avatar.size.width, size / avatar.size.height)
                    let dw = avatar.size.width * s, dh = avatar.size.height * s
                    avatar.draw(in: CGRect(x: circleRect.midX - dw / 2, y: circleRect.midY - dh / 2, width: dw, height: dh))
                    cg.restoreGState()
                } else {
                    // Letter fallback while the photo loads or when there's no avatar URL.
                    UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).setFill()
                    cg.fillEllipse(in: circleRect)
                    let initial = String(name.prefix(1)).uppercased() as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: size * 0.32),
                        .foregroundColor: isMe ? lime : UIColor.white
                    ]
                    let ts = initial.size(withAttributes: attrs)
                    initial.draw(at: CGPoint(x: circleRect.midX - ts.width / 2, y: circleRect.midY - ts.height / 2), withAttributes: attrs)
                }

                // Border ring — route lime, thinned to match the smaller circle.
                lime.setStroke()
                cg.setLineWidth(isSelected ? 1.75 : 1.25)
                cg.strokeEllipse(in: circleRect.insetBy(dx: 1.25, dy: 1.25))

                // Name label above the circle.
                let nx = cx - ns.width / 2
                let ny = (nameBandH - ns.height) / 2
                UIColor(white: 0.1, alpha: 0.75).setFill()
                UIBezierPath(roundedRect: CGRect(x: nx - 4, y: ny - 2, width: ns.width + 8, height: ns.height + 4), cornerRadius: 6).fill()
                name0.draw(at: CGPoint(x: nx, y: ny), withAttributes: nameAttrs)

                // Distance label below the circle.
                if distanceText != nil {
                    let dx = cx - ds.width / 2
                    let dy = nameBandH + size + (distBandH - ds.height) / 2
                    UIColor(white: 0.1, alpha: 0.75).setFill()
                    UIBezierPath(roundedRect: CGRect(x: dx - 4, y: dy - 2, width: ds.width + 8, height: ds.height + 4), cornerRadius: 6).fill()
                    dist.draw(at: CGPoint(x: dx, y: dy), withAttributes: distAttrs)
                }
            }
        }

        // MARK: - Avatar loading

        /// Returns the cached avatar for `urlString`, or nil after kicking off a one-shot fetch.
        /// When the fetch completes, the rider marker(s) using that URL are re-baked with the photo.
        private func avatarImage(for urlString: String?) -> UIImage? {
            guard let urlString, let url = URL(string: urlString) else { return nil }
            if let cached = avatarImages[urlString] { return cached }
            guard !avatarInFlight.contains(urlString) else { return nil }
            avatarInFlight.insert(urlString)
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap { UIImage(data: $0) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.avatarInFlight.remove(urlString)
                    guard let image else { return }
                    self.avatarImages[urlString] = image
                    self.rebakeRiders(withAvatarURL: urlString)
                }
            }.resume()
            return nil   // photo will arrive asynchronously and trigger a re-bake
        }

        /// Re-bake any live rider markers whose pin references `urlString`, now that its photo is
        /// available. The style hash is unchanged, so a plain `applyPins` wouldn't repaint them.
        private func rebakeRiders(withAvatarURL urlString: String) {
            for (id, pin) in pinModels {
                guard case .rider(_, let avatarUrl, _, _, _, _) = pin.style,
                      avatarUrl == urlString,
                      let marker = markers[id] else { continue }
                let baked = renderMarker(pin)
                marker.icon         = baked.image
                marker.groundAnchor = baked.anchor
                pinRenderKeys[id]   = pin.styleHash
            }
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { onInteraction?() }
        }

        // Keep edge indicators glued to the screen border as the camera pans/rotates.
        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            computeEdgeIndicators(mapView)
        }

        // Tapping a dim alternative line selects it.
        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            if let idx = (overlay as? GMSPolyline)?.userData as? Int {
                onSelectRoute?(idx)
            }
        }

        // MARK: - Off-screen rider edge indicators

        /// Projects each off-screen rider to a clamped point on the screen border,
        /// pointing from the user's on-screen position toward the rider's true
        /// bearing. Uses `GMSMapView.projection` so it stays correct under the
        /// nav camera's tilt/heading/padding. Emits nothing when there is no user
        /// pin or the map has no size yet.
        /// Throttled entry point. Coalescing rather than dropping: when a call arrives inside the
        /// window, one trailing pass is scheduled so the chips still settle on the final geometry
        /// instead of freezing at whatever the last un-throttled frame happened to be.
        func computeEdgeIndicators(_ mapView: GMSMapView) {
            guard onEdgeIndicators != nil else { return }
            let waited = Date().timeIntervalSince(lastIndicatorComputeDate)
            guard waited >= Self.minIndicatorInterval else {
                guard !hasPendingIndicatorPass else { return }
                hasPendingIndicatorPass = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (Self.minIndicatorInterval - waited)) { [weak self, weak mapView] in
                    guard let self else { return }
                    self.hasPendingIndicatorPass = false
                    guard let mapView else { return }
                    self.computeEdgeIndicators(mapView)
                }
                return
            }
            lastIndicatorComputeDate = Date()
            computeEdgeIndicatorsNow(mapView)
        }

        private func computeEdgeIndicatorsNow(_ mapView: GMSMapView) {
            guard onEdgeIndicators != nil else { return }
            let bounds = mapView.bounds
            guard bounds.width > 0, bounds.height > 0,
                  let mePin = pinModels["me"] else { emitIndicators([]); return }

            let userCoord = mePin.coordinate
            // A bad "me" fix would make every rider's distance wrong at once, so bail rather than
            // publish a screenful of nonsense.
            guard !Self.isUnsetCoordinate(userCoord) else { emitIndicators([]); return }
            let proj = mapView.projection
            let bearing = mapView.camera.bearing

            // Ray origin = user's on-screen point, clamped inside the inset rect so
            // ray→rect casting always exits through exactly one edge.
            //
            // Plain margins from the map's own edges — the map view's frame already stops
            // above the app's bottom control bar, so a chip clamped inside these bounds
            // cannot land behind it. The bottom margin only has to clear half a chip's
            // height (the clamp point is the chip's center) plus a little breathing room.
            // Top clamps below the app's own chrome when the caller reports it; 96 is the
            // standalone default. Sides and bottom are unchanged.
            //
            // The clamp positions the chip's CENTRE, and its avatar sits above that — the chip is
            // 54pt tall (34 avatar + 3 gap + 17 label), so a 12pt pad left the avatar overhanging
            // by 15pt and still tucked behind the leaderboard. 32pt clears it: half the chip plus
            // a 5pt margin.
            let topInset = topOverlayHeight > 0 ? topOverlayHeight + 32 : 96
            // Sides at 46: the clamp positions the chip's centre, so the inset only has to cover
            // half its width. The widest realistic label ("112.5km") is 30pt from centre, leaving
            // 16pt of margin; 60 held the chips a further 14pt in from each edge for no reason.
            let inset = UIEdgeInsets(top: topInset, left: 46, bottom: 32, right: 46)
            let rect = bounds.inset(by: inset)
            guard rect.width > 0, rect.height > 0 else { emitIndicators([]); return }

            let rawOrigin = proj.point(for: userCoord)
            let origin = CGPoint(
                x: min(max(rawOrigin.x, rect.minX), rect.maxX),
                y: min(max(rawOrigin.y, rect.minY), rect.maxY)
            )

            var out: [EdgeIndicator] = []
            for (id, pin) in pinModels {
                guard case .rider(_, _, let isMe, _, _, _) = pin.style, !isMe else { continue }
                let coord = pin.coordinate
                if proj.contains(coord) { continue }   // on-screen → no chip

                // Relative heading: 0 = straight ahead (up). Screen y is down.
                let theta = (GMSGeometryHeading(userCoord, coord) - bearing) * .pi / 180.0
                let dx = CGFloat(sin(theta))
                let dy = CGFloat(-cos(theta))

                guard !Self.isUnsetCoordinate(coord) else { continue }
                let distance = GMSGeometryDistance(userCoord, coord)

                guard let edge = Self.rayRectExit(origin: origin, dx: dx, dy: dy, rect: rect) else { continue }
                out.append(EdgeIndicator(
                    id: id,
                    edgePoint: edge,
                    arrowAngle: atan2(dy, dx),
                    distanceMeters: distance
                ))
            }
            emitIndicators(out)
        }

        /// Pushes indicators to SwiftUI only when they changed, so the async
        /// recompute in `updateUIView` can't drive an endless render loop.
        private func emitIndicators(_ indicators: [EdgeIndicator]) {
            guard indicators != lastEmittedIndicators else { return }
            lastEmittedIndicators = indicators
            onEdgeIndicators?(indicators)
        }

        /// Exit point of a ray (from an interior `origin`, direction `dx,dy`) through
        /// the border of `rect`. Slab method; returns nil for a degenerate direction.
        static func rayRectExit(origin: CGPoint, dx: CGFloat, dy: CGFloat, rect: CGRect) -> CGPoint? {
            let big: CGFloat = .greatestFiniteMagnitude
            let tx: CGFloat = dx > 0 ? (rect.maxX - origin.x) / dx
                            : dx < 0 ? (rect.minX - origin.x) / dx : big
            let ty: CGFloat = dy > 0 ? (rect.maxY - origin.y) / dy
                            : dy < 0 ? (rect.minY - origin.y) / dy : big
            let t = min(tx, ty)
            guard t.isFinite, t >= 0 else { return nil }
            return CGPoint(x: origin.x + dx * t, y: origin.y + dy * t)
        }
    }
}
