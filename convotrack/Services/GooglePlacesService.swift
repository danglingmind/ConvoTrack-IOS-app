import Foundation
import CoreLocation

// Drop-in replacement for the MKMapItem/MKLocalSearch pattern used in CreateRideView
// and the old coordination prototype. Uses Google Places Text Search REST API — no extra SDK.

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
              let (data, urlResponse) = try? await URLSession.shared.data(from: url),
              (urlResponse as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false,
              let response = try? JSONDecoder().decode(PlacesResponse.self, from: data) else {
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

    /// The street-level place at a coordinate, named the way a rider would say it ("KG Halli,
    /// D' Souza Layout") rather than as a full postal address. Used to give "Your location" a
    /// real name before it is saved as a ride's start: every rider in the ride reads that name,
    /// and to them "Your location" would mean their own.
    static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> PlaceResult? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")!
        components.queryItems = [
            URLQueryItem(name: "latlng", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "result_type", value: "street_address|route|premise|sublocality|locality"),
            URLQueryItem(name: "key", value: GoogleMapsConfig.apiKey)
        ]
        guard let url = components.url,
              let (data, urlResponse) = try? await URLSession.shared.data(from: url),
              (urlResponse as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false,
              let response = try? JSONDecoder().decode(GeocodeResponse.self, from: data),
              let first = response.results.first else {
            return nil
        }
        return PlaceResult(
            id:               first.placeId,
            name:             shortName(fromAddress: first.formattedAddress),
            coordinate:       coordinate,
            formattedAddress: first.formattedAddress
        )
    }

    /// The first two parts of an address that aren't house or plot numbers ("67/1", "263/3"), or
    /// Google's "Unnamed Road", which names nothing a rider could look for.
    static func shortName(fromAddress address: String) -> String {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let named = parts.filter { part in
            let digits = part.filter(\.isNumber).count
            return digits * 2 < part.count && part.caseInsensitiveCompare("Unnamed Road") != .orderedSame
        }
        let picked = (named.isEmpty ? parts : named).prefix(2)
        return picked.joined(separator: ", ")
    }
}

// MARK: - Response models (private)

private struct GeocodeResponse: Decodable {
    let results: [Item]

    struct Item: Decodable {
        let placeId: String
        let formattedAddress: String
        enum CodingKeys: String, CodingKey {
            case placeId          = "place_id"
            case formattedAddress = "formatted_address"
        }
    }
}

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
