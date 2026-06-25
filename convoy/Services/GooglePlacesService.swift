import Foundation
import CoreLocation

// Drop-in replacement for the MKMapItem/MKLocalSearch pattern used in CreateRideView
// and CoordinationOverlayView. Uses Google Places Text Search REST API — no extra SDK.

struct PlaceResult: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let formattedAddress: String?

    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

enum GooglePlacesService {

    static func search(query: String, near userLocation: CLLocation?) async -> [PlaceResult] {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/textsearch/json")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "key",   value: GoogleMapsConfig.apiKey)
        ]
        if let loc = userLocation {
            items += [
                URLQueryItem(name: "location", value: "\(loc.coordinate.latitude),\(loc.coordinate.longitude)"),
                URLQueryItem(name: "radius",   value: "50000")
            ]
        }
        components.queryItems = items
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response  = try? JSONDecoder().decode(PlacesResponse.self, from: data) else {
            return []
        }

        return response.results.map { r in
            PlaceResult(
                id:               r.placeId,
                name:             r.name,
                coordinate:       CLLocationCoordinate2D(latitude: r.geometry.location.lat,
                                                         longitude: r.geometry.location.lng),
                formattedAddress: r.formattedAddress
            )
        }
    }
}

// MARK: - Response models (private)

private struct PlacesResponse: Decodable {
    let results: [PlaceItem]

    struct PlaceItem: Decodable {
        let placeId: String
        let name: String
        let geometry: Geometry
        let formattedAddress: String?
        enum CodingKeys: String, CodingKey {
            case placeId          = "place_id"
            case name, geometry
            case formattedAddress = "formatted_address"
        }
    }

    struct Geometry: Decodable { let location: LatLng }
    struct LatLng: Decodable   { let lat: Double; let lng: Double }
}
