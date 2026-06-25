import UIKit
import CoreLocation

// Replaces MKMapSnapshotter for the ride-summary share card.
// Returns a UIImage fetched from the Google Static Maps API.

enum GoogleStaticMapsService {

    static func snapshot(
        routeCoordinates: [CLLocationCoordinate2D],
        waypoints: [Waypoint],
        size: CGSize = CGSize(width: 390, height: 700),
        scale: Int = 2
    ) async -> UIImage? {
        guard !routeCoordinates.isEmpty else { return nil }

        let encodedPath = GoogleDirectionsService.encodePolyline(routeCoordinates)

        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "size",    value: "\(Int(size.width))x\(Int(size.height))"),
            URLQueryItem(name: "scale",   value: "\(scale)"),
            URLQueryItem(name: "maptype", value: "roadmap"),
            URLQueryItem(name: "style",   value: "feature:all|element:geometry|color:0x131313"),
            URLQueryItem(name: "style",   value: "feature:road|element:geometry|color:0x2c2c2c"),
            URLQueryItem(name: "style",   value: "feature:water|element:geometry|color:0x000000"),
            URLQueryItem(name: "style",   value: "feature:poi|visibility:off"),
            URLQueryItem(name: "style",   value: "feature:all|element:labels.text.fill|color:0x616161"),
            URLQueryItem(name: "path",    value: "color:0xcaf300ff|weight:4|enc:\(encodedPath)"),
            URLQueryItem(name: "key",     value: GoogleMapsConfig.apiKey)
        ]

        // Add waypoint markers
        let sorted = waypoints.sorted { $0.order < $1.order }
        for wp in sorted {
            let color: String
            switch wp.type {
            case "START":       color = "0x62ff96"
            case "DESTINATION": color = "0xcaf300"
            default:            color = "0xffffff"
            }
            items.append(URLQueryItem(
                name:  "markers",
                value: "color:\(color)|size:tiny|\(wp.lat),\(wp.lng)"
            ))
        }

        components.queryItems = items
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

        return UIImage(data: data)
    }
}
