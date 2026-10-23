import Foundation
import SwiftUI
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

/// The quick searches riders reach for on a ride: fuel, food and somewhere worth stopping.
enum PlaceCategory: String, CaseIterable, Identifiable {
    case fuel, food, viewpoint

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fuel:      "Fuel"
        case .food:      "Food"
        case .viewpoint: "Viewpoints"
        }
    }

    var systemImage: String {
        switch self {
        case .fuel:      "fuelpump.fill"
        case .food:      "fork.knife"
        case .viewpoint: "mountain.2.fill"
        }
    }

    /// Sent to Places as the text query: the words a rider would type.
    var query: String {
        switch self {
        case .fuel:      "petrol pump"
        case .food:      "restaurant"
        case .viewpoint: "viewpoint"
        }
    }
}

/// A place found along the route, with how much longer the ride gets for stopping there.
struct PlaceSearchHit: Identifiable {
    let place: PlaceResult
    /// Extra riding time to call in on the way. Nil when it can't be worked out (a route that
    /// already has stops between start and destination).
    var detourSeconds: TimeInterval?
    var id: String { place.id }
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

    // MARK: Places API (New)

    /// Text search biased to a circle around `center` (Places API New), for the category chips.
    static func searchText(_ query: String, near center: CLLocationCoordinate2D?,
                           radiusMeters: Double = 15_000) async -> [PlaceResult] {
        var body: [String: Any] = ["textQuery": query, "maxResultCount": 10, "languageCode": "en"]
        if let center {
            body["locationBias"] = ["circle": [
                "center": ["latitude": center.latitude, "longitude": center.longitude],
                "radius": radiusMeters
            ]]
        }
        let response = await placesSearch(body, fieldMask: placeFields)
        return response?.places?.compactMap(\.result) ?? []
    }

    /// Places near the route, ranked by Google for how little they take the ride off it (Places
    /// API New `searchAlongRouteParameters`). With `measuresDetours`, each hit carries its detour:
    /// the time to it from the start plus on to the destination, less the route on its own.
    ///
    /// Both sides of that subtraction are traffic-free. Places times its legs without traffic
    /// whatever `routingPreference` says (measured: identical figures either way), so the route
    /// is re-timed traffic-free to match; against the planner's traffic-aware time every detour
    /// came out about 12 minutes short and most read "No detour".
    static func searchAlongRoute(_ query: String, route: [CLLocationCoordinate2D],
                                 measuresDetours: Bool,
                                 avoiding avoidances: RouteAvoidances = .none) async -> [PlaceSearchHit] {
        guard let origin = route.first, route.count >= 2 else { return [] }
        // An even sample keeps the request small; a few hundred points is plenty for "near the
        // route" at search precision.
        let sampleCount = min(route.count, 400)
        let sampled = (0..<sampleCount).map { route[(route.count - 1) * $0 / max(sampleCount - 1, 1)] }
        let body: [String: Any] = [
            "textQuery": query,
            "maxResultCount": 10,
            "languageCode": "en",
            "searchAlongRouteParameters": [
                "polyline": ["encodedPolyline": GoogleDirectionsService.encodePolyline(sampled)]
            ],
            "routingParameters": [
                "origin": ["latitude": origin.latitude, "longitude": origin.longitude]
            ]
        ]
        async let baseline: TimeInterval? = measuresDetours
            ? try? await GoogleDirectionsService.route(through: [origin, route[route.count - 1]],
                                                       trafficAware: false, avoiding: avoidances).durationSeconds
            : nil
        guard let response = await placesSearch(body, fieldMask: placeFields + ",routingSummaries"),
              let places = response.places else { return [] }
        let directSeconds = await baseline
        let summaries = response.routingSummaries ?? []
        return places.enumerated().compactMap { i, item in
            guard let place = item.result else { return nil }
            var detour: TimeInterval?
            if let directSeconds, summaries.indices.contains(i), let legs = summaries[i].legs, !legs.isEmpty {
                let viaPlace = legs.reduce(0) { $0 + parseDuration($1.duration) }
                detour = max(0, viaPlace - directSeconds)
            }
            return PlaceSearchHit(place: place, detourSeconds: detour)
        }
    }

    private static let placeFields = "places.id,places.displayName,places.formattedAddress,places.location"

    private static func placesSearch(_ body: [String: Any], fieldMask: String) async -> NewPlacesResponse? {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GoogleMapsConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data
        guard let (responseData, urlResponse) = try? await URLSession.shared.data(for: request),
              (urlResponse as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false else {
            return nil
        }
        return try? JSONDecoder().decode(NewPlacesResponse.self, from: responseData)
    }

    /// Places API durations come as "383s".
    private static func parseDuration(_ raw: String?) -> TimeInterval {
        guard let raw else { return 0 }
        return TimeInterval(raw.hasSuffix("s") ? String(raw.dropLast()) : raw) ?? 0
    }

    // MARK: Geocoding

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

private struct NewPlacesResponse: Decodable {
    let places: [Item]?
    let routingSummaries: [RoutingSummary]?

    struct Item: Decodable {
        let id: String
        let displayName: LocalizedText?
        let formattedAddress: String?
        let location: LatLng?

        var result: PlaceResult? {
            guard let location, let name = displayName?.text else { return nil }
            return PlaceResult(id: id, name: name,
                               coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                               formattedAddress: formattedAddress)
        }
    }
    struct LocalizedText: Decodable { let text: String }
    struct LatLng: Decodable { let latitude: Double; let longitude: Double }
    struct RoutingSummary: Decodable { let legs: [Leg]? }
    struct Leg: Decodable { let duration: String? }
}

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
