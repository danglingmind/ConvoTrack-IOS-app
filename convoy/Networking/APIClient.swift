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

    private let baseURL = URL(string: "https://convoy-backend-hx3c.onrender.com")!

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
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
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
}
