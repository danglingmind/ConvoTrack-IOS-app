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
        mapView.isUserInteractionEnabled = isInteractive

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

        var routeLine:         GMSPolyline? = nil
        var originalRouteLine: GMSPolyline? = nil
        var routeVersion         = 0
        var originalRouteVersion = 0

        var markers:       [String: GMSMarker] = [:]
        var pinStyleHashes:[String: Int]        = [:]

        var lastCameraId: UUID? = nil

        // Route decorations — end-cap dots and curved dotted connectors
        var endCapMarkers:    [GMSMarker]   = []
        var connectorLines:   [GMSPolyline] = []
        var decorationVersion: Int = 0

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
                pinStyleHashes.removeValue(forKey: id)
            }

            for pin in pins {
                let newHash = pin.styleHash
                if let marker = markers[pin.id] {
                    // Always update position (riders move)
                    marker.position = pin.coordinate
                    // Only re-render icon if style changed
                    if pinStyleHashes[pin.id] != newHash {
                        pinStyleHashes[pin.id] = newHash
                        marker.icon = renderIcon(pin)
                    }
                } else {
                    let marker = GMSMarker()
                    marker.position     = pin.coordinate
                    marker.groundAnchor = pin.anchorBottom ? CGPoint(x: 0.5, y: 1.0) : CGPoint(x: 0.5, y: 0.5)
                    marker.icon         = renderIcon(pin)
                    marker.zIndex       = 5   // above end-cap markers (zIndex 2)
                    marker.map          = mapView
                    markers[pin.id]     = marker
                    pinStyleHashes[pin.id] = newHash
                }
            }
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

        private func renderIcon(_ pin: MapPin) -> UIImage? {
            switch pin.style {
            case .userLocation(let heading):
                return renderUserLocationIcon(heading: heading)
            case .simpleDot(let color, let size):
                return renderDotIcon(color: color, size: size)
            case .destination(let name):
                return renderSwiftUI(DestinationPin(name: name), size: CGSize(width: 80, height: 100))
            case .waypoint(let name):
                return renderSwiftUI(WaypointPin(name: name), size: CGSize(width: 80, height: 80))
            case .lobbyStart:
                return renderSwiftUI(LobbyStartPin(), size: CGSize(width: 70, height: 80))
            case .regroup(let type):
                return renderSwiftUI(RegroupPin(type: type), size: CGSize(width: 70, height: 90))
            case .rider(let name, _, let isMe, let rank, let isSelected):
                return renderRiderIcon(name: name, isMe: isMe, rank: rank, isSelected: isSelected)
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

        private func renderRiderIcon(name: String, isMe: Bool, rank: Int, isSelected: Bool) -> UIImage? {
            let size: CGFloat = isSelected ? 54 : 46
            let lime = UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)
            let border = isSelected ? lime : (isMe ? lime : UIColor.white.withAlphaComponent(0.9))
            let totalH = size + 6 + 18  // circle + triangle + label
            let scale  = UIScreen.main.scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size + 8, height: totalH), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f
            }())
            return renderer.image { ctx in
                let cx = (size + 8) / 2
                // Circle background
                UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: (8/2), y: 0, width: size, height: size))
                // Initials
                let initial = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: size * 0.32),
                    .foregroundColor: isMe ? lime : UIColor.white
                ]
                let textSize = (initial as NSString).size(withAttributes: attrs)
                (initial as NSString).draw(at: CGPoint(x: cx - textSize.width / 2 + 4, y: size / 2 - textSize.height / 2), withAttributes: attrs)
                // Border ring
                border.setStroke()
                ctx.cgContext.setLineWidth(isSelected ? 3 : 2.5)
                ctx.cgContext.strokeEllipse(in: CGRect(x: 4 + 1.5, y: 1.5, width: size - 3, height: size - 3))
                // Rank badge
                let rankText = "#\(rank)" as NSString
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .black),
                    .foregroundColor: rank == 1 ? UIColor(red: 0.09, green: 0.12, blue: 0, alpha: 1) : UIColor.white
                ]
                let badgeSize = rankText.size(withAttributes: badgeAttrs)
                let bx = (8/2) + size - badgeSize.width - 4
                let by = size - badgeSize.height - 2
                (rank == 1 ? lime : UIColor(white: 0.22, alpha: 0.95)).setFill()
                UIBezierPath(roundedRect: CGRect(x: bx - 2, y: by - 1, width: badgeSize.width + 4, height: badgeSize.height + 2), cornerRadius: 4).fill()
                rankText.draw(at: CGPoint(x: bx, y: by), withAttributes: badgeAttrs)
                // Triangle pointer
                let triPath = UIBezierPath()
                triPath.move(to:    CGPoint(x: cx, y: size + 6))
                triPath.addLine(to: CGPoint(x: cx - 5, y: size))
                triPath.addLine(to: CGPoint(x: cx + 5, y: size))
                triPath.close()
                UIColor.white.setFill()
                triPath.fill()
                // Name label
                let label = name.components(separatedBy: " ").first?.uppercased() ?? ""
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: isSelected ? 9 : 8, weight: .black),
                    .foregroundColor: UIColor.white
                ]
                let ls = (label as NSString).size(withAttributes: labelAttrs)
                let lx = cx - ls.width / 2
                let ly = size + 8
                UIColor(white: 0.1, alpha: 0.75).setFill()
                UIBezierPath(roundedRect: CGRect(x: lx - 4, y: ly - 2, width: ls.width + 8, height: ls.height + 4), cornerRadius: 6).fill()
                (label as NSString).draw(at: CGPoint(x: lx, y: ly), withAttributes: labelAttrs)
            }
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            if gesture { onInteraction?() }
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
