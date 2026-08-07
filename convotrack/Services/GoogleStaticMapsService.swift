import UIKit
import CoreLocation

// Renders the label-free, poster-style route map used by the ride-summary share card.
//
// Unlike a plain Static Maps request, this returns a `StaticMapSnapshot` bundling the
// image with the exact center/zoom it was rendered at, so the share card can project
// our own waypoint coordinates to pixel positions and draw named markers on top —
// Google's built-in markers can't carry full-text labels, and we turn off every map
// label so the only names on the card are ours.

struct StaticMapSnapshot {
    let image: UIImage
    let center: CLLocationCoordinate2D
    let zoom: Int
    let size: CGSize   // points (pre-scale); matches the card's display space

    /// Pixel position of a coordinate within the card's `size`-point space.
    func point(for coord: CLLocationCoordinate2D) -> CGPoint {
        StaticMapProjection.point(coord, center: center, zoom: zoom, size: size)
    }
}

enum GoogleStaticMapsService {

    // Static Maps free tier caps each dimension at 640pt, so the map hero is 390×640
    // (top-anchored in the taller card); scale:2 renders it at 780×1280px.
    static func snapshot(
        routeCoordinates: [CLLocationCoordinate2D],
        waypoints: [Waypoint],
        size: CGSize = CGSize(width: 390, height: 640),
        scale: Int = 2
    ) async -> StaticMapSnapshot? {
        guard !routeCoordinates.isEmpty else { return nil }

        // Fit the route inside a band that leaves room for the top brand and the
        // bottom meta block, then bias the map center so the route sits centered in
        // that band rather than dead-center of the map.
        let band = CGRect(x: 44, y: 150, width: size.width - 88, height: 300)
        let bboxCenter = StaticMapProjection.boundingCenter(routeCoordinates)
        let zoom = StaticMapProjection.fitZoom(routeCoordinates, rect: band.size, maxZoom: 17)
        let center = StaticMapProjection.center(
            anchoring: bboxCenter,
            at: CGPoint(x: band.midX, y: band.midY),
            zoom: zoom,
            size: size
        )

        let encodedPath = GoogleDirectionsService.encodePolyline(routeCoordinates)

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        components.queryItems = [
            URLQueryItem(name: "center",  value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "zoom",    value: "\(zoom)"),
            URLQueryItem(name: "size",    value: "\(Int(size.width))x\(Int(size.height))"),
            URLQueryItem(name: "scale",   value: "\(scale)"),
            URLQueryItem(name: "maptype", value: "roadmap"),
            // Near-black desaturated basemap, no labels — the poster look.
            URLQueryItem(name: "style",   value: "feature:all|element:labels|visibility:off"),
            URLQueryItem(name: "style",   value: "feature:all|element:geometry|color:0x131313"),
            URLQueryItem(name: "style",   value: "feature:road|element:geometry|color:0x262626"),
            URLQueryItem(name: "style",   value: "feature:road.highway|element:geometry|color:0x2f2f2f"),
            URLQueryItem(name: "style",   value: "feature:water|element:geometry|color:0x0a0a0a"),
            URLQueryItem(name: "style",   value: "feature:landscape|element:geometry|color:0x161616"),
            URLQueryItem(name: "style",   value: "feature:poi|visibility:off"),
            URLQueryItem(name: "style",   value: "feature:transit|visibility:off"),
            // Route: bold lime outline, the hero of the card.
            URLQueryItem(name: "path",    value: "color:0xcaf300ff|weight:5|enc:\(encodedPath)"),
            URLQueryItem(name: "key",     value: GoogleMapsConfig.apiKey)
        ]

        guard let url = components.url,
              let (data, urlResponse) = try? await URLSession.shared.data(from: url),
              (urlResponse as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false,
              let image = UIImage(data: data) else {
            return nil
        }
        return StaticMapSnapshot(image: image, center: center, zoom: zoom, size: size)
    }
}

// MARK: - Web Mercator projection

// Standard Google Maps Web Mercator, world = 256·2^zoom pixels at the equator.
enum StaticMapProjection {

    private static func worldPoint(_ coord: CLLocationCoordinate2D, worldSize: Double) -> CGPoint {
        let x = (coord.longitude + 180) / 360 * worldSize
        let sinLat = min(max(sin(coord.latitude * .pi / 180), -0.9999), 0.9999)
        let y = (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * .pi)) * worldSize
        return CGPoint(x: x, y: y)
    }

    private static func coordinate(fromWorld p: CGPoint, worldSize: Double) -> CLLocationCoordinate2D {
        let lng = p.x / worldSize * 360 - 180
        let yMerc = (0.5 - p.y / worldSize) * 2 * .pi
        let lat = (2 * atan(exp(yMerc)) - .pi / 2) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Pixel position of `coord` in a `size`-point image centered on `center` at `zoom`.
    static func point(_ coord: CLLocationCoordinate2D, center: CLLocationCoordinate2D, zoom: Int, size: CGSize) -> CGPoint {
        let worldSize = 256.0 * pow(2.0, Double(zoom))
        let world = worldPoint(coord, worldSize: worldSize)
        let centerWorld = worldPoint(center, worldSize: worldSize)
        return CGPoint(
            x: world.x - centerWorld.x + size.width / 2,
            y: world.y - centerWorld.y + size.height / 2
        )
    }

    /// The map center that makes `anchor` land at pixel `p` within `size`.
    static func center(anchoring anchor: CLLocationCoordinate2D, at p: CGPoint, zoom: Int, size: CGSize) -> CLLocationCoordinate2D {
        let worldSize = 256.0 * pow(2.0, Double(zoom))
        let anchorWorld = worldPoint(anchor, worldSize: worldSize)
        let centerWorld = CGPoint(
            x: anchorWorld.x - (p.x - size.width / 2),
            y: anchorWorld.y - (p.y - size.height / 2)
        )
        return coordinate(fromWorld: centerWorld, worldSize: worldSize)
    }

    static func boundingCenter(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lngs.min() ?? 0) + (lngs.max() ?? 0)) / 2
        )
    }

    /// Largest integer zoom that fits the route's bounding box inside `rect` points.
    static func fitZoom(_ coords: [CLLocationCoordinate2D], rect: CGSize, maxZoom: Int) -> Int {
        guard let minLat = coords.map(\.latitude).min(),
              let maxLat = coords.map(\.latitude).max(),
              let minLng = coords.map(\.longitude).min(),
              let maxLng = coords.map(\.longitude).max() else { return 14 }

        func mercY(_ lat: Double) -> Double {
            let s = min(max(sin(lat * .pi / 180), -0.9999), 0.9999)
            return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi)   // [0,1], north=0
        }

        let latFraction = mercY(minLat) - mercY(maxLat)         // > 0
        var lngDelta = maxLng - minLng
        if lngDelta < 0 { lngDelta += 360 }
        let lngFraction = lngDelta / 360

        guard latFraction > 0, lngFraction > 0 else { return 14 }

        let zoomLat = log2(Double(rect.height) / 256 / latFraction)
        let zoomLng = log2(Double(rect.width) / 256 / lngFraction)
        let zoom = Int(floor(min(zoomLat, zoomLng)))
        return min(max(zoom, 2), maxZoom)
    }
}
