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

// MARK: - Service

enum GoogleDirectionsService {

    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> DirectionsResult {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        components.queryItems = [
            URLQueryItem(name: "origin",      value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "mode",        value: "driving"),
            URLQueryItem(name: "key",         value: GoogleMapsConfig.apiKey)
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(DirectionsResponse.self, from: data)

        guard let route = response.routes.first,
              let leg   = route.legs.first else {
            throw URLError(.cannotParseResponse)
        }

        let coords = decodePolyline(route.overviewPolyline.points)
        let steps = leg.steps.map { step in
            DirectionsStep(
                instruction:    stripHTML(step.htmlInstructions),
                endCoordinate:  CLLocationCoordinate2D(latitude: step.endLocation.lat, longitude: step.endLocation.lng),
                distanceMeters: Double(step.distance.value)
            )
        }

        return DirectionsResult(
            coordinates:     coords,
            distanceMeters:  Double(leg.distance.value),
            durationSeconds: TimeInterval(leg.duration.value),
            steps:           steps
        )
    }

    // MARK: - Polyline codec

    static func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0, lng = 0

        while index < encoded.endIndex {
            var shift = 0, result = 0, b: Int
            repeat {
                guard index < encoded.endIndex else { break }
                b = Int(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20

            lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1
            shift = 0; result = 0

            repeat {
                guard index < encoded.endIndex else { break }
                b = Int(encoded[index].asciiValue! - 63)
                index = encoded.index(after: index)
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20

            lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return coords
    }

    // Encode to Google polyline format (already used in CreateRideView — kept here for single source)
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
            result.append(Character(UnicodeScalar((0x20 | (v & 0x1f)) + 63)!))
            v >>= 5
        }
        result.append(Character(UnicodeScalar(v + 63)!))
        return result
    }

    private static func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }
}

// MARK: - Response models (private)

private struct DirectionsResponse: Decodable {
    let routes: [Route]

    struct Route: Decodable {
        let overviewPolyline: Polyline
        let legs: [Leg]
        enum CodingKeys: String, CodingKey {
            case overviewPolyline = "overview_polyline"
            case legs
        }
    }

    struct Polyline: Decodable { let points: String }

    struct Leg: Decodable {
        let distance: MeasureValue
        let duration: MeasureValue
        let steps: [Step]
    }

    struct Step: Decodable {
        let htmlInstructions: String
        let endLocation: LatLng
        let distance: MeasureValue
        enum CodingKeys: String, CodingKey {
            case htmlInstructions = "html_instructions"
            case endLocation      = "end_location"
            case distance
        }
    }

    struct LatLng: Decodable { let lat: Double; let lng: Double }
    struct MeasureValue: Decodable { let value: Int }
}
