import Foundation
import CoreLocation

/// Destinations the rider planned rides to, newest first. Kept on this device only, the way
/// Google Maps keeps recent searches, and never sent anywhere (no coordinates or place names
/// leave the phone through analytics either — `docs/analytics.md`).
enum RecentDestinations {
    private static let key = "planner.recentDestinations"
    static let limit = 8

    private struct Entry: Codable {
        let id: String
        let name: String
        let address: String?
        let lat: Double
        let lng: Double
    }

    static func load() -> [PlaceResult] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map {
            PlaceResult(id: $0.id, name: $0.name,
                        coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng),
                        formattedAddress: $0.address)
        }
    }

    /// Moves `place` to the front, dropping an older copy of it and anything past `limit`.
    static func remember(_ place: PlaceResult) {
        var places = load().filter { $0.id != place.id }
        places.insert(place, at: 0)
        let entries = places.prefix(limit).map {
            Entry(id: $0.id, name: $0.name, address: $0.formattedAddress,
                  lat: $0.coordinate.latitude, lng: $0.coordinate.longitude)
        }
        if let data = try? JSONEncoder().encode(Array(entries)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
