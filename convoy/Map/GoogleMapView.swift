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
    var routeCoords: [CLLocationCoordinate2D] = []
    var rerouteCoords: [CLLocationCoordinate2D] = []
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

        c.applyRoute(routeCoords,   to: mapView, key: &c.routeVersion,   line: &c.routeLine,   color: UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1),   width: 5, dashed: false, zIndex: 100)
        c.applyRoute(rerouteCoords, to: mapView, key: &c.rerouteVersion, line: &c.rerouteLine, color: UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1), width: 4, dashed: true,  zIndex: 99)
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

        var routeLine:   GMSPolyline? = nil
        var rerouteLine: GMSPolyline? = nil
        var routeVersion   = 0
        var rerouteVersion = 0

        var markers:       [String: GMSMarker] = [:]
        var pinStyleHashes:[String: Int]        = [:]

        var lastCameraId: UUID? = nil

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
            let newVersion = coords.count
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
