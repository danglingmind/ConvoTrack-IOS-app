import Foundation
import ClerkKit

enum APIClientError: Error, LocalizedError {
    case notAuthenticated
    case serverError(String)
    case decodingError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:        return "Not signed in"
        case .serverError(let msg):    return msg
        case .decodingError:           return "Failed to parse server response"
        case .networkError(let err):   return err.localizedDescription
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = AppURLs.backendBaseURL

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private init() {}

    // MARK: - Auth Token

    private func getToken() async throws -> String {
        guard let token = try await Clerk.shared.auth.getToken() else {
            throw APIClientError.notAuthenticated
        }
        return token
    }

    // MARK: - Request Builder

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        let token = try await getToken()

        // Split off any query string. appendingPathComponent percent-encodes the whole
        // string (turning "?" into "%3F"), which would fold the query into the path and
        // break routing. Attach the query separately via URLComponents instead.
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(parts[0])
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(pathOnly),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIClientError.networkError(URLError(.badURL))
        }
        if parts.count > 1 {
            // Values are already URL-safe (numbers, codes); keep them as-is.
            components.percentEncodedQuery = String(parts[1])
        }
        guard let url = components.url else {
            throw APIClientError.networkError(URLError(.badURL))
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = body
        return req
    }

    // MARK: - Generic Fetch

    private func fetch<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let req = try await makeRequest(path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let apiErr = try? decoder.decode(APIError.self, from: data)
            throw APIClientError.serverError(apiErr?.error ?? "HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decodingError
        }
    }

    private func fetchVoid(_ path: String, method: String = "GET", body: Data? = nil) async throws {
        let req = try await makeRequest(path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let apiErr = try? decoder.decode(APIError.self, from: data)
            throw APIClientError.serverError(apiErr?.error ?? "HTTP \(http.statusCode)")
        }
    }

    // MARK: - Ride Endpoints

    func createRide(_ request: CreateRideRequest) async throws -> CreateRideResponse {
        let body = try encoder.encode(request)
        return try await fetch("/rides", method: "POST", body: body)
    }

    func updateRide(_ rideId: String, _ request: UpdateRideRequest) async throws {
        let body = try encoder.encode(request)
        try await fetchVoid("/rides/\(rideId)", method: "PATCH", body: body)
    }

    func getRide(_ rideId: String) async throws -> Ride {
        return try await fetch("/rides/\(rideId)")
    }

    func getRideByInviteCode(_ code: String) async throws -> InviteCodeResponse {
        return try await fetch("/rides/join/\(code)")
    }

    func joinRide(_ rideId: String) async throws {
        try await fetchVoid("/rides/\(rideId)/join", method: "POST")
    }

    func startRide(_ rideId: String) async throws {
        try await fetchVoid("/rides/\(rideId)/start", method: "POST")
    }

    func endRide(_ rideId: String) async throws {
        try await fetchVoid("/rides/\(rideId)/end", method: "POST")
    }

    func getRideSummary(_ rideId: String) async throws -> RideSummary {
        return try await fetch("/rides/\(rideId)/summary")
    }

    func getMyRides() async throws -> [HistoryRide] {
        let response: MyRidesResponse = try await fetch("/rides/me")
        return response.rides
    }

    func syncProfile(name: String, avatarUrl: String?) async throws {
        struct Body: Encodable { let name: String; let avatarUrl: String? }
        let body = try encoder.encode(Body(name: name, avatarUrl: avatarUrl))
        try await fetchVoid("/users/me", method: "PATCH", body: body)
    }

    func updateProfile(_ req: UpdateProfileRequest) async throws {
        let body = try encoder.encode(req)
        try await fetchVoid("/users/me", method: "PATCH", body: body)
    }

    func getNearbyRides(lat: Double, lng: Double) async throws -> [NearbyRide] {
        let resp: NearbyRidesResponse = try await fetch(
            "/rides/nearby?lat=\(lat)&lng=\(lng)&radiusKm=20"
        )
        return resp.rides
    }

    // MARK: - Membership Endpoints

    func fetchMe() async throws -> UserMeResponse {
        return try await fetch("/users/me")
    }

    func activateMembership(signedTransaction: String) async throws -> ActivateMembershipResponse {
        let body = try encoder.encode(ActivateMembershipRequest(signedTransaction: signedTransaction))
        return try await fetch("/memberships/activate", method: "POST", body: body)
    }
}
