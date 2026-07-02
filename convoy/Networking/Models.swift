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

struct UpdateRideRequest: Codable {
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

struct RideUpdatedEvent: Codable {
    let rideId: String
    let title: String
    let destinationName: String
    let destinationLat: Double
    let destinationLng: Double
    let distanceMeters: Double
    let estimatedDurationSeconds: Int
    let maxAllowedParticipants: Int
    let waypoints: [Waypoint]
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

// MARK: - Membership

struct MembershipPlanInfo: Codable {
    let code: String
    let isPremium: Bool
    let maxRidersPerRide: Int
    let monthlyLimit: Int?
    let rideHistoryDays: Int
    let analyticsEnabled: Bool
    let endsAt: String?
}

struct UserMeResponse: Codable {
    let userId: String
    let name: String
    let avatarUrl: String?
    let username: String?
    let phone: String?
    let phoneVisible: Bool
    let emailContact: String?
    let emailContactVisible: Bool
    let notifyNearbyRides: Bool
    let plan: MembershipPlanInfo

    // Default values for Bool fields so older API responses decode gracefully
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId               = try c.decode(String.self,  forKey: .userId)
        name                 = try c.decode(String.self,  forKey: .name)
        avatarUrl            = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        username             = try c.decodeIfPresent(String.self, forKey: .username)
        phone                = try c.decodeIfPresent(String.self, forKey: .phone)
        phoneVisible         = try c.decodeIfPresent(Bool.self,   forKey: .phoneVisible)         ?? false
        emailContact         = try c.decodeIfPresent(String.self, forKey: .emailContact)
        emailContactVisible  = try c.decodeIfPresent(Bool.self,   forKey: .emailContactVisible)  ?? false
        notifyNearbyRides    = try c.decodeIfPresent(Bool.self,   forKey: .notifyNearbyRides)    ?? true
        plan                 = try c.decode(MembershipPlanInfo.self, forKey: .plan)
    }
}

struct UpdateProfileRequest: Encodable {
    var username: String?
    var phone: String?
    var phoneVisible: Bool?
    var emailContact: String?
    var emailContactVisible: Bool?
    var notifyNearbyRides: Bool?
}

struct ActivateMembershipRequest: Codable {
    let signedTransaction: String
}

struct ActivateMembershipResponse: Codable {
    let ok: Bool
    let plan: MembershipPlanInfo
}

// MARK: - Nearby Rides

struct NearbyRide: Codable, Identifiable {
    let id: String
    let title: String
    let status: String
    let destinationName: String
    let distanceMeters: Double
    let startLat: Double
    let startLng: Double
    let distanceFromUserKm: Double
    let riderCount: Int
    let maxParticipants: Int
    let leaderName: String
    let leaderId: String
    let inviteCode: String
    let viewerRole: String?   // "LEADER" | "MEMBER" | nil (not part of this ride)

    var isLive: Bool { status != "LOBBY" }   // ACTIVE / PAUSED → live; LOBBY → forming
    var isFull: Bool { riderCount >= maxParticipants }
    var isMine: Bool { viewerRole == "LEADER" }
    var isJoined: Bool { viewerRole == "MEMBER" }
    var isParticipant: Bool { viewerRole != nil }

    var formattedRideDistance: String {
        let km = distanceMeters / 1000
        return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
    }

    var formattedUserDistance: String {
        distanceFromUserKm < 1
            ? String(format: "%.0f m away", distanceFromUserKm * 1000)
            : String(format: "%.1f km away", distanceFromUserKm)
    }
}

struct NearbyRidesResponse: Codable {
    let rides: [NearbyRide]
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
