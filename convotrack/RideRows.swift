import SwiftUI
import CoreLocation

// MARK: - Ride row (Home recents, History)

struct RideRow: View {
    let ride: HistoryRide

    private var isCompleted: Bool { ride.status == "COMPLETED" }

    private var detail: String {
        let iso = ride.endedAt ?? ride.startedAt ?? ride.createdAt
        var parts: [String] = []
        if let iso, let date = Self.parse(iso) {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        // Duration is shown on completed rides only.
        if isCompleted, let seconds = ride.durationSeconds, seconds > 0 {
            parts.append(RideDuration.inline(seconds))
        }
        return parts.joined(separator: " · ")
    }

    /// The API sends fractional seconds ("…:00.000Z"), which a default ISO8601DateFormatter rejects.
    private static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private var distance: String {
        ride.distanceMeters > 0 ? String(format: "%.1f km", ride.distanceMeters / 1000) : "--"
    }

    var body: some View {
        DSRideRowCard(
            title: ride.title,
            distance: distance,
            detail: detail,
            isLeader: ride.isLeader == true,
            inProgress: !isCompleted
        ) {
            RideThumbnail(rideId: ride.rideId, isCompleted: isCompleted)
        }
    }
}

/// Destination photo for a ride row. The history list doesn't carry the destination, so this
/// reads it from the ride (once per ride, remembered) and goes through the same cached
/// `GooglePlacePhotoService` as the lobby and the active-ride card. A neutral tile stands in
/// until a photo arrives, and stays if the destination has none.
struct RideThumbnail: View {
    let rideId: String
    let isCompleted: Bool
    @State private var photo: UIImage?

    /// Remembered per ride so scrolling the list doesn't refetch the ride, but only for
    /// `destinationTTL` and dropped on edit/delete/sign-out, so an edited destination
    /// can't keep showing the old place's photo (the photo cache itself is keyed by place).
    @MainActor private static var destinations: [String: (name: String, coordinate: CLLocationCoordinate2D, fetched: Date)] = [:]
    private static let destinationTTL: TimeInterval = 600

    /// The same mapping on disk, so a history row can still find its photo with no network. Only
    /// read when the ride fetch fails: whenever the app is online the fresh ride wins, so an edit
    /// made on another phone is picked up as soon as there is a connection. Lives in Caches/ (the OS
    /// may purge it) and is emptied by the same calls that empty the in-memory copy.
    private struct StoredDestination: Codable { let name: String; let lat: Double; let lng: Double }
    private static let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("RideDestinations.json")
    private static let storeLimit = 300
    @MainActor private static var stored: [String: StoredDestination] = {
        guard let url = storeURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: StoredDestination].self, from: data) else { return [:] }
        return decoded
    }()

    @MainActor private static func persist() {
        guard let url = storeURL else { return }
        if stored.count > storeLimit { for key in stored.keys.prefix(stored.count - storeLimit) { stored[key] = nil } }
        if let data = try? JSONEncoder().encode(stored) { try? data.write(to: url, options: .atomic) }
    }

    @MainActor static func forgetDestination(rideId: String) {
        destinations[rideId] = nil
        if stored.removeValue(forKey: rideId) != nil { persist() }
    }

    @MainActor static func forgetAllDestinations() {
        destinations.removeAll()
        stored.removeAll()
        if let url = storeURL { try? FileManager.default.removeItem(at: url) }
    }

    var body: some View {
        ZStack {
            DS.Surface.raised
            Image(systemName: isCompleted ? "flag.checkered" : "location.north.fill")
                .dsIcon(DS.IconSize.lg)
                .foregroundStyle(isCompleted ? DS.Text.secondary.base : DS.Accent.base)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            }
        }
        .allowsHitTesting(false)
        .task(id: rideId) { await load() }
    }

    @MainActor
    private func load() async {
        var destination = Self.destinations[rideId].flatMap {
            -$0.fetched.timeIntervalSinceNow < Self.destinationTTL ? $0 : nil
        }
        if destination == nil, let ride = try? await APIClient.shared.getRide(rideId), !ride.destinationName.isEmpty {
            destination = (ride.destinationName, CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng), Date())
            Self.destinations[rideId] = destination
            Self.stored[rideId] = StoredDestination(name: ride.destinationName, lat: ride.destinationLat, lng: ride.destinationLng)
            Self.persist()
        } else if destination == nil, let saved = Self.stored[rideId] {
            // Offline (or the ride is unreachable): the last destination we saw still finds its
            // cached photo.
            destination = (saved.name, CLLocationCoordinate2D(latitude: saved.lat, longitude: saved.lng), .distantPast)
        }
        guard let destination, !Task.isCancelled else { return }
        if let fetched = await GooglePlacePhotoService.shared.photo(destinationName: destination.name, coordinate: destination.coordinate) {
            photo = fetched.image
        }
    }
}
