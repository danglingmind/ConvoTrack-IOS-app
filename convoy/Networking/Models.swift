import Foundation

// MARK: - Auth

struct ConvoyUser: Codable {
    let id: String
    let name: String
    let avatarUrl: String?
}

// MARK: - Ride

struct Ride: Codable {
    let id: String
    let title: String
    let status: String
    let leaderId: String
    let inviteCode: String
    let destinationName: String
    let destinationLat: Double
    let destinationLng: Double
    let distanceMeters: Double
    let estimatedDurationSeconds: Int
    let maxAllowedParticipants: Int
    let startedAt: String?
    let endedAt: String?
    let createdAt: String?
    let waypoints: [Waypoint]
    let participants: [RideParticipant]
}

struct Waypoint: Codable {
    let order: Int
    let name: String
    let type: String
    let lat: Double
    let lng: Double
}

struct RideParticipant: Codable {
    let userId: String
    let name: String
    let avatarUrl: String?
    let status: String
    let isLeader: Bool
    let joinedAt: String
}

// MARK: - Create Ride

struct CreateRideRequest: Codable {
    let title: String
    let destinationName: String
    let destinationLat: Double
    let destinationLng: Double
    let distanceMeters: Double
    let estimatedDurationSeconds: Int
    let maxAllowedParticipants: Int
    let routePolyline: String
    let waypoints: [CreateWaypoint]
}

struct CreateWaypoint: Codable {
    let order: Int
    let name: String
    let type: String
    let lat: Double
    let lng: Double
}

struct CreateRideResponse: Codable {
    let rideId: String
    let inviteCode: String
}


// MARK: - Invite Code Lookup

struct InviteCodeResponse: Codable {
    let rideId: String
    let title: String
    let leaderName: String
    let participantCount: Int
    let maxParticipants: Int
    let status: String
}

// MARK: - Socket.IO Live State

struct RegroupEvent: Codable, Equatable {
    let regroupId: String
    let type: String       // "FUEL" | "FOOD" | "SCENIC" | "STOP"
    let lat: Double
    let lng: Double
    let createdBy: String
    let createdAt: String
}

struct RideStateUpdate: Codable {
    let rideId: String
    let status: String
    let participants: [LiveParticipant]
    let leaderboard: [LiveLeaderboardEntry]
    let openRegroup: RegroupEvent?
}

struct LiveParticipant: Codable {
    let userId: String
    let lat: Double?
    let lng: Double?
    let speed: Double?
    let heading: Double?
    let progress: Double
    let offRoute: Bool
    let updatedAt: String?
    let battery: Double?
    let signalStrength: String?
}

struct LiveLeaderboardEntry: Codable {
    let rank: Int
    let userId: String
    let name: String
    let progress: Double
    let gapMeters: Double
    let positionDelta: Int
    let title: String?
}

// MARK: - Ride Summary

struct RideSummary: Codable {
    let rideId: String
    let durationSeconds: Int
    let distanceMeters: Double
    let avgSpeedKmh: Double?
    let maxGroupSplitMeters: Double
    let compactnessScore: Double
    let totalRegroups: Int
    let totalEmergencies: Int
    let createdAt: String
    let participants: [SummaryParticipant]
}

struct SummaryParticipant: Codable {
    let userId: String
    let name: String
    let avatarUrl: String?
    let rideTitle: String?
    let syncScore: Int?
}

// MARK: - Ride History

struct MyRidesResponse: Codable {
    let rides: [HistoryRide]
}

struct HistoryRide: Codable, Identifiable {
    var id: String { rideId }
    let rideId: String
    let title: String
    let status: String
    let isLeader: Bool?
    let inviteCode: String?
    let startedAt: String?
    let endedAt: String?
    let createdAt: String?
    let distanceMeters: Double
    let durationSeconds: Int?
    let avgSpeedKmh: Double?
    let compactnessScore: Double?
}

// MARK: - API Errors

struct APIError: Codable {
    let error: String
}

// MARK: - Client-Side Title Display

func displayTitle(_ raw: String?) -> String {
    switch raw {
    case "RIDE_LEADER":     return "RIDE LEADER"
    case "PACE_KEEPER":     return "PACE KEEPER"
    case "TRAIL_GUARDIAN":  return "TRAIL GUARDIAN"
    case "FORMATION_RIDER": return "FORMATION RIDER"
    default:                return raw ?? ""
    }
}
