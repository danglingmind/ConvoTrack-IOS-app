import Foundation
import CoreLocation

// MARK: - Result types

struct DirectionsResult {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let steps: [DirectionsStep]
}

struct DirectionsStep {
    let instruction: String
    let endCoordinate: CLLocationCoordinate2D
    let distanceMeters: Double
}

/// One selectable alternative for a direct origin→destination route.
struct RouteOption: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    let label: String?   // Routes API routeLabels, e.g. DEFAULT_ROUTE / FUEL_EFFICIENT
}

// MARK: - Service

enum GoogleDirectionsService {

    // trafficAware=true for route planning; false for fast reroute requests (< 500ms)
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        trafficAware: Bool = true
    ) async throws -> DirectionsResult {
        // Routes API v2 — POST, higher-density polylines, traffic-aware
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GoogleMapsConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Only request the fields we actually use to keep response small
        request.setValue(
            "routes.legs.distanceMeters,routes.legs.duration," +
            "routes.legs.steps.distanceMeters,routes.legs.steps.endLocation," +
            "routes.legs.steps.navigationInstruction,routes.legs.steps.polyline",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let body: [String: Any] = [
            "origin": [
                "location": ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]
            ],
            "destination": [
                "location": ["latLng": ["latitude": destination.latitude, "longitude": destination.longitude]]
            ],
            "travelMode": "DRIVE",
            "routingPreference": trafficAware ? "TRAFFIC_AWARE" : "TRAFFIC_UNAWARE",
            "polylineQuality": "HIGH_QUALITY",
            "computeAlternativeRoutes": false,
            "languageCode": "en-US",
            "units": "METRIC"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let response = try JSONDecoder().decode(RoutesResponse.self, from: data)

        guard let route = response.routes.first,
              let leg   = route.legs?.first else {
            throw URLError(.cannotParseResponse)
        }

        // Stitch per-step HIGH_QUALITY polylines for lane-accurate geometry
        let coords = leg.steps.flatMap { decodePolyline($0.polyline.encodedPolyline) }
        let steps: [DirectionsStep] = leg.steps.compactMap { step in
            guard let end = step.endLocation else { return nil }
            return DirectionsStep(
                instruction:    step.navigationInstruction?.instructions ?? "",
                endCoordinate:  CLLocationCoordinate2D(latitude: end.latLng.latitude,
                                                       longitude: end.latLng.longitude),
                distanceMeters: Double(step.distanceMeters ?? 0)
            )
        }

        return DirectionsResult(
            coordinates:     coords,
            distanceMeters:  Double(leg.distanceMeters),
            durationSeconds: parseDuration(leg.duration),
            steps:           steps
        )
    }

    /// Alternative whole-trip routes for a DIRECT origin→destination request.
    /// Google's Routes API returns no alternatives when intermediate waypoints are
    /// present, so callers use this only for the no-middle-stop case.
    static func alternativeRoutes(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        trafficAware: Bool = true
    ) async throws -> [RouteOption] {
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GoogleMapsConfig.apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Whole-route fields (one polyline per alternative) — no per-step data needed here
        request.setValue(
            "routes.polyline.encodedPolyline,routes.distanceMeters," +
            "routes.duration,routes.routeLabels",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        let body: [String: Any] = [
            "origin": [
                "location": ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]
            ],
            "destination": [
                "location": ["latLng": ["latitude": destination.latitude, "longitude": destination.longitude]]
            ],
            "travelMode": "DRIVE",
            "routingPreference": trafficAware ? "TRAFFIC_AWARE" : "TRAFFIC_UNAWARE",
            "polylineQuality": "HIGH_QUALITY",
            "computeAlternativeRoutes": true,
            "languageCode": "en-US",
            "units": "METRIC"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let response = try JSONDecoder().decode(RoutesResponse.self, from: data)

        return response.routes.compactMap { route in
            guard let encoded = route.polyline?.encodedPolyline else { return nil }
            return RouteOption(
                coordinates:     decodePolyline(encoded),
                distanceMeters:  Double(route.distanceMeters ?? 0),
                durationSeconds: parseDuration(route.duration ?? "0s"),
                label:           route.routeLabels?.first
            )
        }
    }

    // Routes API duration comes as "123s" or "1.5s"
    private static func parseDuration(_ raw: String) -> TimeInterval {
        let s = raw.hasSuffix("s") ? String(raw.dropLast()) : raw
        return TimeInterval(Double(s) ?? 0)
    }

    /// Decodes a stored route polyline into coordinates, or nil if absent/too short to draw.
    /// Used by ride views to render the leader-selected route instead of recomputing a default.
    static func decodedRoute(_ polyline: String?) -> [CLLocationCoordinate2D]? {
        guard let encoded = polyline, !encoded.isEmpty else { return nil }
        let coords = decodePolyline(encoded)
        return coords.count >= 2 ? coords : nil
    }

    // MARK: - Polyline codec (Google encoded polyline algorithm — unchanged)

    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0, lng = 0

        while index < encoded.endIndex {
            var shift = 0, result = 0, b = 0
            repeat {
                guard index < encoded.endIndex else { break }
                guard let ascii = encoded[index].asciiValue else { break }
                b = Int(ascii - 63)
                index = encoded.index(after: index)
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20
            lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1
            shift = 0; result = 0; b = 0

            repeat {
                guard index < encoded.endIndex else { break }
                guard let ascii = encoded[index].asciiValue else { break }
                b = Int(ascii - 63)
                index = encoded.index(after: index)
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20
            lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1

            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5,
                                                 longitude: Double(lng) / 1e5))
        }
        return coords
    }

    static func encodePolyline(_ coordinates: [CLLocationCoordinate2D]) -> String {
        var result = ""
        var prevLat = 0, prevLng = 0
        for coord in coordinates {
            let lat = Int(round(coord.latitude  * 1e5))
            let lng = Int(round(coord.longitude * 1e5))
            result += encodeValue(lat - prevLat)
            result += encodeValue(lng - prevLng)
            prevLat = lat; prevLng = lng
        }
        return result
    }

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : value << 1
        var result = ""
        while v >= 0x20 {
            if let scalar = UnicodeScalar((0x20 | (v & 0x1f)) + 63) {
                result.append(Character(scalar))
            }
            v >>= 5
        }
        if let scalar = UnicodeScalar(v + 63) {
            result.append(Character(scalar))
        }
        return result
    }
}

// MARK: - Routes API v2 response models

private struct RoutesResponse: Decodable {
    let routes: [Route]

    struct Route: Decodable {
        let legs: [Leg]?                 // absent in the alternatives field mask
        let polyline: RoutePolyline?     // whole-route polyline (alternatives request)
        let distanceMeters: Int?
        let duration: String?
        let routeLabels: [String]?
    }

    struct RoutePolyline: Decodable {
        let encodedPolyline: String
    }

    struct Leg: Decodable {
        let distanceMeters: Int
        let duration: String
        let steps: [Step]
    }

    struct Step: Decodable {
        let distanceMeters: Int?
        let endLocation: EndLocation?
        let navigationInstruction: NavigationInstruction?
        let polyline: StepPolyline
    }

    struct StepPolyline: Decodable {
        let encodedPolyline: String
    }

    struct EndLocation: Decodable {
        let latLng: LatLng
    }

    struct LatLng: Decodable {
        let latitude: Double
        let longitude: Double
    }

    struct NavigationInstruction: Decodable {
        let instructions: String
    }
}
