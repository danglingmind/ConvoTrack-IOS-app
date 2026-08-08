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
        case rider(name: String, avatarUrl: String?, isMe: Bool, rank: Int, isSelected: Bool)
        case regroup(type: String)
        case emergency
        case simpleDot(color: UIColor, size: CGFloat)
    }

    let id: String
    let coordinate: CLLocationCoordinate2D
    let style: Style
    var anchorBottom: Bool = true   // false → center anchor (simpleDot)

    var styleHash: Int {
        var h = Hasher()
        switch style {
        case .userLocation(let deg):
            h.combine(0); h.combine(Int(deg))
        case .destination(let n):
            h.combine(1); h.combine(n)
        case .waypoint(let n):
            h.combine(2); h.combine(n)
        case .lobbyStart:
            h.combine(3)
        case .rider(let n, _, let me, let rank, let sel):
            h.combine(4); h.combine(n); h.combine(me); h.combine(rank); h.combine(sel)
        case .regroup(let t):
            h.combine(5); h.combine(t)
        case .simpleDot(_, let sz):
            h.combine(6); h.combine(Int(sz))
        case .emergency:
            h.combine(7)
        }
        return h.finalize()
    }
}

// MARK: - Camera command

struct MapCameraCommand {
    let id: UUID
    enum Action {
        case fitCoords([CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool)
        case navigate(lat: Double, lng: Double, zoom: Float, bearing: Double, tilt: Double, animated: Bool)
    }
    let action: Action

    static func fitRoute(_ coords: [CLLocationCoordinate2D], padding: CGFloat = 48, animated: Bool = false) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .fitCoords(coords, padding: UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding), animated: animated))
    }

    static func fitRouteInsets(_ coords: [CLLocationCoordinate2D], top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .fitCoords(coords, padding: UIEdgeInsets(top: top, left: left, bottom: bottom, right: right), animated: animated))
    }

    static func follow(lat: Double, lng: Double, speed: Double, bearing: Double, animated: Bool = true) -> MapCameraCommand {
        let zoom: Float = speed < 20 ? 17.5 : (speed < 60 ? 16.5 : 16.0)
        return MapCameraCommand(id: UUID(), action: .navigate(lat: lat, lng: lng, zoom: zoom, bearing: bearing, tilt: 0, animated: animated))
    }

    static func focus(lat: Double, lng: Double, zoom: Float = 15, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(id: UUID(), action: .navigate(lat: lat, lng: lng, zoom: zoom, bearing: 0, tilt: 0, animated: animated))
    }
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
    var onInteraction: (() -> Void)? = nil
    /// All alternative routes (index == position). The one at `selectedRouteIndex`
    /// is drawn bright via `routeCoords`; the rest render dim + tappable.
    var alternativeRoutes: [[CLLocationCoordinate2D]] = []
    var selectedRouteIndex: Int = 0
    var onSelectRoute: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView(frame: .zero, camera: GMSCameraPosition(latitude: 0, longitude: 0, zoom: 2))
        applyDarkStyle(to: mapView)
        mapView.isMyLocationEnabled = false
        mapView.isTrafficEnabled    = true
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
        mapView.isUserInteractionEnabled = isInteractive

        // Dim, tappable alternatives sit below the bright selected route.
        c.applyAlternatives(alternativeRoutes, selectedIndex: selectedRouteIndex, to: mapView)
        c.applyRoute(originalRouteCoords, to: mapView, key: &c.originalRouteVersion, line: &c.originalRouteLine, color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 0.28), width: 3, dashed: false, zIndex: 98)
        c.applyRoute(routeCoords,         to: mapView, key: &c.routeVersion,         line: &c.routeLine,         color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1),    width: 5, dashed: false, zIndex: 100)
        c.applyRouteDecorations(routeCoords: routeCoords, originalCoords: originalRouteCoords, stopCoords: stopCoords, to: mapView)
        c.applyPins(pins, to: mapView)

        if let cmd = cameraCommand, cmd.id != c.lastCameraId {
            c.lastCameraId = cmd.id
            c.applyCamera(cmd, to: mapView)
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

        var routeLine:         GMSPolyline? = nil
        var originalRouteLine: GMSPolyline? = nil
        var routeVersion         = 0
        var originalRouteVersion = 0

        // Dim, tappable alternative routes (userData carries the global index)
        var altLines:   [GMSPolyline] = []
        var altVersion: Int = 0

        var markers:       [String: GMSMarker] = [:]
        var pinRenderKeys: [String: Int]        = [:]   // styleHash ⊕ quantized offset

        // Avatar photos for rider markers. Baking a marker icon is synchronous, so each avatar
        // is fetched once, cached by URL, and the affected rider marker(s) re-baked when it lands.
        var avatarImages:   [String: UIImage] = [:]
        var avatarInFlight: Set<String>       = []

        // Marker collision state — see resolveCollisions(on:)
        var pinModels:   [String: MapPin]   = [:]       // last pin per id, to re-bake on offset change
        var pinOffsets:  [String: CGVector] = [:]       // current (quantized) body displacement per id
        var pinBodyGeom: [String: BodyGeom] = [:]       // body disc geometry per id, for detection

        /// Body-box geometry relative to the tip (true coordinate), in screen points.
        struct BodyGeom {
            let defaultCenterOffset: CGVector  // body-box center at rest, relative to tip
            let halfSize: CGSize               // half the body box
            let movable: Bool                  // riders move; stops / user arrow are obstacles
        }

        // Collision tuning
        static let collisionMaxLeader: CGFloat = 60
        static let collisionQuantum:   CGFloat = 8   // offset grid; deadbands micro-jitter

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

            line?.map = nil
            line = nil
            guard !coords.isEmpty else { return }

            let path = GMSMutablePath()
            coords.forEach { path.add($0) }

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
            to mapView: GMSMapView
        ) {
            // Version hash over all endpoints so we redraw only on actual changes
            let newVersion: Int = {
                var h = Hasher()
                for coord in [routeCoords.first, routeCoords.last,
                               originalCoords.first, originalCoords.last,
                               stopCoords.first, stopCoords.last].compactMap({ $0 }) {
                    h.combine(coord.latitude.bitPattern)
                    h.combine(coord.longitude.bitPattern)
                }
                h.combine(stopCoords.count)
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
            // Stop pins get zIndex 5 (set in applyPins).

            // End caps on original planned route (dim)
            if let first = originalCoords.first {
                endCapMarkers.append(endCapMarker(at: first, size: 14, opacity: 0.45, zIndex: 2, to: mapView))
            }
            if let last = originalCoords.last {
                endCapMarkers.append(endCapMarker(at: last,  size: 14, opacity: 0.45, zIndex: 2, to: mapView))
            }

            // End caps on active route (bright) — always draw both endpoints.
            // In navigation the route start is the road-projected position, which differs
            // from the GPS-position user-pin, so it IS clearly visible.
            if let first = routeCoords.first {
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
                pinOffsets.removeValue(forKey: id)
                pinBodyGeom.removeValue(forKey: id)
            }

            for pin in pins {
                pinModels[pin.id] = pin
                let offset  = pinOffsets[pin.id] ?? .zero
                let newKey  = renderKey(pin.styleHash, offset)

                if let marker = markers[pin.id] {
                    // Always update position (riders move)
                    marker.position = pin.coordinate
                    // Re-render only when style OR collision offset changed
                    if pinRenderKeys[pin.id] != newKey {
                        pinRenderKeys[pin.id] = newKey
                        let baked = renderMarker(pin, offset: offset)
                        marker.icon = baked.image
                        pinBodyGeom[pin.id] = baked.geom
                    }
                } else {
                    let baked = renderMarker(pin, offset: offset)
                    let marker = GMSMarker()
                    marker.position     = pin.coordinate
                    // Collidable pins are baked tip-centered → constant center anchor.
                    marker.groundAnchor = isCollidable(pin.style) ? CGPoint(x: 0.5, y: 0.5)
                                        : (pin.anchorBottom ? CGPoint(x: 0.5, y: 1.0) : CGPoint(x: 0.5, y: 0.5))
                    marker.icon         = baked.image
                    marker.zIndex       = 5   // above end-cap markers (zIndex 2)
                    marker.map          = mapView
                    markers[pin.id]     = marker
                    pinRenderKeys[pin.id] = newKey
                    pinBodyGeom[pin.id]   = baked.geom
                }
            }

            resolveCollisions(on: mapView)
        }

        private func renderKey(_ styleHash: Int, _ offset: CGVector) -> Int {
            var h = Hasher()
            h.combine(styleHash)
            h.combine(Int((offset.dx / Self.collisionQuantum).rounded()))
            h.combine(Int((offset.dy / Self.collisionQuantum).rounded()))
            return h.finalize()
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

            case .navigate(let lat, let lng, let zoom, let bearing, let tilt, let animated):
                // In 3D nav mode (tilt > 0), push the viewport center downward so the user
                // marker sits in the lower third and more of the route ahead is visible.
                if tilt > 0 && mapView.bounds.height > 0 {
                    mapView.padding = UIEdgeInsets(top: mapView.bounds.height * 0.30, left: 0, bottom: 0, right: 0)
                } else {
                    mapView.padding = .zero
                }
                let pos = GMSCameraPosition(latitude: lat, longitude: lng, zoom: zoom, bearing: bearing, viewingAngle: tilt)
                if animated { mapView.animate(to: pos) } else { mapView.camera = pos }
            }
        }

        // MARK: Icon rendering

        private func isCollidable(_ style: MapPin.Style) -> Bool {
            switch style {
            case .rider, .destination, .waypoint, .regroup, .emergency: return true
            default: return false
            }
        }

        private func isMovable(_ style: MapPin.Style) -> Bool {
            if case .rider = style { return true }
            return false
        }

        /// Body art for a collidable pin plus the point within it that is the semantic
        /// tip (the pixel that must sit on the true coordinate), and a leader accent color.
        private func renderBody(_ pin: MapPin) -> (image: UIImage, anchorInBody: CGPoint, accent: UIColor)? {
            let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)
            switch pin.style {
            case .destination(let name):
                guard let img = renderSwiftUIFit(DestinationPin(name: name)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height), lime)
            case .waypoint(let name):
                guard let img = renderSwiftUIFit(WaypointPin(name: name)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height), lime)
            case .regroup(let type):
                guard let img = renderSwiftUI(RegroupPin(type: type), size: CGSize(width: 70, height: 90)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height), UIColor(red: 1, green: 0.72, blue: 0.24, alpha: 1))
            case .emergency:
                guard let img = renderSwiftUI(EmergencyPin(), size: CGSize(width: 70, height: 90)) else { return nil }
                return (img, CGPoint(x: img.size.width / 2, y: img.size.height), UIColor(red: 1, green: 0.706, blue: 0.671, alpha: 1))
            case .rider(let name, let avatarUrl, let isMe, let rank, let isSelected):
                let size: CGFloat = isSelected ? 54 : 46
                // Cached photo if we have it; nil triggers an async fetch + re-bake and draws the
                // letter fallback in the meantime.
                let avatar = avatarImage(for: avatarUrl)
                guard let img = renderRiderIcon(name: name, avatar: avatar, isMe: isMe, rank: rank, isSelected: isSelected) else { return nil }
                // Triangle tip within the rider canvas is at (width/2, size+6).
                return (img, CGPoint(x: img.size.width / 2, y: size + 6), (isMe || isSelected) ? lime : .white)
            default:
                return nil
            }
        }

        /// Renders a marker icon plus its collision geometry. Collidable pins are baked
        /// into a tip-centered canvas so `groundAnchor` stays (0.5,0.5) at any offset,
        /// with a leader line from the fixed tip to the displaced body.
        func renderMarker(_ pin: MapPin, offset: CGVector) -> (image: UIImage?, geom: BodyGeom) {
            if isCollidable(pin.style), let body = renderBody(pin) {
                let composed = composeOffsetIcon(body: body.image, anchorInBody: body.anchorInBody,
                                                 offset: offset, accent: body.accent)
                let w = body.image.size.width, h = body.image.size.height
                let geom = BodyGeom(
                    defaultCenterOffset: CGVector(dx: w / 2 - body.anchorInBody.x,
                                                  dy: h / 2 - body.anchorInBody.y),
                    halfSize: CGSize(width: w / 2, height: h / 2),
                    movable: isMovable(pin.style)
                )
                return (composed, geom)
            }

            // Non-collidable — original path; geometry used only as an obstacle.
            let image: UIImage?
            switch pin.style {
            case .userLocation(let heading): image = renderUserLocationIcon(heading: heading)
            case .simpleDot(let c, let s):   image = renderDotIcon(color: c, size: s)
            case .lobbyStart:                image = renderSwiftUI(LobbyStartPin(), size: CGSize(width: 70, height: 80))
            default:                         image = nil
            }
            let sz = image?.size ?? .zero
            let centered: Bool = { if case .userLocation = pin.style { return true } else { return false } }()
            let geom = BodyGeom(
                defaultCenterOffset: centered ? .zero : CGVector(dx: 0, dy: -sz.height / 2),
                halfSize: CGSize(width: sz.width / 2, height: sz.height / 2),
                movable: false
            )
            return (image, geom)
        }

        /// Composites `body` into a tip-centered canvas (tip at center → constant
        /// (0.5,0.5) ground anchor), drawing the body displaced by `offset` with a
        /// dashed leader line back to the tip. `offset == .zero` reproduces the resting
        /// look (tip on the coordinate, no leader).
        private func composeOffsetIcon(body: UIImage, anchorInBody: CGPoint, offset: CGVector, accent: UIColor) -> UIImage {
            let w = body.size.width, h = body.size.height
            let leftExt = anchorInBody.x, rightExt = w - anchorInBody.x
            let topExt  = anchorInBody.y, botExt   = h - anchorInBody.y
            let maxLeader = Self.collisionMaxLeader
            let halfW = maxLeader + max(leftExt, rightExt)
            let halfH = maxLeader + max(topExt, botExt)
            let canvas = CGSize(width: halfW * 2, height: halfH * 2)
            let center = CGPoint(x: halfW, y: halfH)                    // tip = true coordinate
            let bodyAnchor = CGPoint(x: center.x + offset.dx, y: center.y + offset.dy)

            let renderer = UIGraphicsImageRenderer(size: canvas, format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = UIScreen.main.scale; return f
            }())
            return renderer.image { ctx in
                let c = ctx.cgContext
                if hypot(offset.dx, offset.dy) > 3 {
                    c.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
                    c.setLineWidth(1.5)
                    c.setLineDash(phase: 0, lengths: [3, 3])
                    c.move(to: center)
                    c.addLine(to: bodyAnchor)
                    c.strokePath()
                    c.setLineDash(phase: 0, lengths: [])
                    // Tip dot marking the exact true location
                    c.setFillColor(accent.cgColor)
                    c.fillEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                    c.setStrokeColor(UIColor(white: 0.07, alpha: 1).cgColor)
                    c.setLineWidth(1)
                    c.strokeEllipse(in: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5))
                }
                body.draw(at: CGPoint(x: bodyAnchor.x - anchorInBody.x, y: bodyAnchor.y - anchorInBody.y))
            }
        }

        private func renderSwiftUI<V: View>(_ view: V, size: CGSize) -> UIImage? {
            let renderer = ImageRenderer(content:
                view.preferredColorScheme(.dark)
                    .frame(width: size.width, height: size.height)
            )
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage
        }

        /// Renders a pin at its intrinsic size (no fixed canvas), so labels that
        /// wrap to a second line are not clipped. The view itself caps its label
        /// width (via `.frame(maxWidth:)`), which bounds the marker's footprint so
        /// a long name can't sprawl across the screen even when the pin sits at a
        /// corner. The pin content is horizontally centered, so the default
        /// bottom-center ground anchor still sits the marker over its coordinate.
        private func renderSwiftUIFit<V: View>(_ view: V) -> UIImage? {
            let renderer = ImageRenderer(content: view.preferredColorScheme(.dark))
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage
        }

        private func renderUserLocationIcon(heading: Double) -> UIImage {
            let s: CGFloat = 46
            let scale = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: {
                let f = UIGraphicsImageRendererFormat()
                f.scale = scale
                return f
            }())
            return renderer.image { ctx in
                let cgCtx = ctx.cgContext
                let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)

                // Outer glow
                cgCtx.setFillColor(lime.withAlphaComponent(0.22).cgColor)
                cgCtx.fillEllipse(in: CGRect(x: 0, y: 0, width: s, height: s))

                // Inner circle
                let inner: CGFloat = 24
                let inset = (s - inner) / 2
                cgCtx.setShadow(offset: .zero, blur: 10, color: lime.withAlphaComponent(0.9).cgColor)
                cgCtx.setFillColor(lime.cgColor)
                cgCtx.fillEllipse(in: CGRect(x: inset, y: inset, width: inner, height: inner))
                cgCtx.setShadow(offset: .zero, blur: 0, color: UIColor.clear.cgColor)

                // White border
                cgCtx.setStrokeColor(UIColor.white.cgColor)
                cgCtx.setLineWidth(3)
                cgCtx.strokeEllipse(in: CGRect(x: inset + 1.5, y: inset + 1.5, width: inner - 3, height: inner - 3))

                // Arrow pointing up (heading applied via transform on the marker isn't possible,
                // so we rotate the image itself)
                let arrowPath = UIBezierPath()
                let cx = s / 2, cy = s / 2
                arrowPath.move(to:    CGPoint(x: cx, y: cy - 7))
                arrowPath.addLine(to: CGPoint(x: cx - 4, y: cy + 4))
                arrowPath.addLine(to: CGPoint(x: cx + 4, y: cy + 4))
                arrowPath.close()
                cgCtx.setFillColor(UIColor(red: 0.09, green: 0.12, blue: 0, alpha: 1).cgColor)
                arrowPath.fill()
            }
            // Rotate the image to match heading
            .rotated(by: CGFloat(heading * .pi / 180))
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

        private func renderRiderIcon(name: String, avatar: UIImage?, isMe: Bool, rank: Int, isSelected: Bool) -> UIImage? {
            let size: CGFloat = isSelected ? 54 : 46
            let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)
            let border = (isSelected || isMe) ? lime : UIColor.white.withAlphaComponent(0.9)

            // Measure the label up front so the canvas can widen to fit it. Previously the canvas
            // was a fixed `size + 8` wide and any name longer than the circle was clipped.
            let label = (name.components(separatedBy: " ").first?.uppercased() ?? "") as NSString
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: isSelected ? 9 : 8, weight: .black),
                .foregroundColor: UIColor.white
            ]
            let ls = label.size(withAttributes: labelAttrs)
            let labelBoxW = ceil(ls.width) + 8          // capsule horizontal padding
            let canvasW   = max(size + 8, labelBoxW)
            let totalH    = size + 6 + 18               // circle + triangle + label
            let cx        = canvasW / 2
            let circleRect = CGRect(x: cx - size / 2, y: 0, width: size, height: size)

            let scale  = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasW, height: totalH), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
            }())
            return renderer.image { ctx in
                let cg = ctx.cgContext

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

                // Border ring
                border.setStroke()
                cg.setLineWidth(isSelected ? 3 : 2.5)
                cg.strokeEllipse(in: circleRect.insetBy(dx: 1.5, dy: 1.5))

                // Rank badge (bottom-right of the circle)
                let rankText = "#\(rank)" as NSString
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .black),
                    .foregroundColor: rank == 1 ? UIColor(red: 0.09, green: 0.12, blue: 0, alpha: 1) : UIColor.white
                ]
                let badgeSize = rankText.size(withAttributes: badgeAttrs)
                let bx = circleRect.maxX - badgeSize.width - 4
                let by = size - badgeSize.height - 2
                (rank == 1 ? lime : UIColor(white: 0.22, alpha: 0.95)).setFill()
                UIBezierPath(roundedRect: CGRect(x: bx - 2, y: by - 1, width: badgeSize.width + 4, height: badgeSize.height + 2), cornerRadius: 4).fill()
                rankText.draw(at: CGPoint(x: bx, y: by), withAttributes: badgeAttrs)

                // Triangle pointer (tip at cx, size+6 — the marker's semantic anchor)
                let triPath = UIBezierPath()
                triPath.move(to:    CGPoint(x: cx, y: size + 6))
                triPath.addLine(to: CGPoint(x: cx - 5, y: size))
                triPath.addLine(to: CGPoint(x: cx + 5, y: size))
                triPath.close()
                UIColor.white.setFill()
                triPath.fill()

                // Name label — canvas is guaranteed wide enough, so it never clips.
                let lx = cx - ls.width / 2
                let ly = size + 8
                UIColor(white: 0.1, alpha: 0.75).setFill()
                UIBezierPath(roundedRect: CGRect(x: lx - 4, y: ly - 2, width: ls.width + 8, height: ls.height + 4), cornerRadius: 6).fill()
                label.draw(at: CGPoint(x: lx, y: ly), withAttributes: labelAttrs)
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
                guard case .rider(_, let avatarUrl, _, _, _) = pin.style,
                      avatarUrl == urlString,
                      let marker = markers[id] else { continue }
                let offset = pinOffsets[id] ?? .zero
                let baked = renderMarker(pin, offset: offset)
                marker.icon             = baked.image
                pinBodyGeom[id]         = baked.geom
                pinRenderKeys[id]       = renderKey(pin.styleHash, offset)
            }
        }

        // MARK: - Collision resolution

        /// Projects every marker to screen space, resolves body overlaps (tips fixed),
        /// and re-bakes only the icons whose quantized offset actually changed. Cheap:
        /// one projection + O(n²) box tests over ~30 markers, re-raster gated by deadband.
        func resolveCollisions(on mapView: GMSMapView) {
            guard mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }

            var inputs: [MarkerCollisionResolver.Marker] = []
            for (id, marker) in markers {
                guard let geom = pinBodyGeom[id] else { continue }
                let tip = mapView.projection.point(for: marker.position)
                inputs.append(.init(
                    id: id,
                    tip: tip,
                    defaultCenter: CGPoint(x: tip.x + geom.defaultCenterOffset.dx,
                                           y: tip.y + geom.defaultCenterOffset.dy),
                    halfSize: geom.halfSize,
                    movable: geom.movable,
                    prevOffset: pinOffsets[id] ?? .zero
                ))
            }
            guard inputs.contains(where: { $0.movable }) else { return }

            let solved = MarkerCollisionResolver.resolve(inputs, maxLeader: Self.collisionMaxLeader)
            let q = Self.collisionQuantum

            for input in inputs where input.movable {
                let raw = solved[input.id] ?? .zero
                let quantized = CGVector(dx: (raw.dx / q).rounded() * q,
                                         dy: (raw.dy / q).rounded() * q)
                let prev = pinOffsets[input.id] ?? .zero
                // Deadband: skip sub-quantum changes so nothing re-bakes on jitter.
                if abs(quantized.dx - prev.dx) < 0.5, abs(quantized.dy - prev.dy) < 0.5 { continue }

                pinOffsets[input.id] = quantized
                guard let pin = pinModels[input.id], let marker = markers[input.id] else { continue }
                let baked = renderMarker(pin, offset: quantized)
                marker.icon = baked.image
                pinBodyGeom[input.id]   = baked.geom
                pinRenderKeys[input.id] = renderKey(pin.styleHash, quantized)
            }
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { onInteraction?() }
        }

        // Tapping a dim alternative line selects it.
        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            if let idx = (overlay as? GMSPolyline)?.userData as? Int {
                onSelectRoute?(idx)
            }
        }

        // Pan/zoom don't re-run updateUIView, so re-declutter when the camera settles.
        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            resolveCollisions(on: mapView)
        }
    }
}

// MARK: - UIImage rotation helper

private extension UIImage {
    func rotated(by radians: CGFloat) -> UIImage {
        guard radians != 0 else { return self }
        let newSize = CGSize(
            width:  abs(cos(radians)) * size.width  + abs(sin(radians)) * size.height,
            height: abs(sin(radians)) * size.width  + abs(cos(radians)) * size.height
        )
        let renderer = UIGraphicsImageRenderer(size: newSize, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
        }())
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.cgContext.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
