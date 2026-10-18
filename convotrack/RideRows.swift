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

    @MainActor private static var destinations: [String: (name: String, coordinate: CLLocationCoordinate2D)] = [:]

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
        var destination = Self.destinations[rideId]
        if destination == nil, let ride = try? await APIClient.shared.getRide(rideId), !ride.destinationName.isEmpty {
            destination = (ride.destinationName, CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng))
            Self.destinations[rideId] = destination
        }
        guard let destination, !Task.isCancelled else { return }
        if let fetched = await GooglePlacePhotoService.shared.photo(destinationName: destination.name, coordinate: destination.coordinate) {
            photo = fetched.image
        }
    }
}
