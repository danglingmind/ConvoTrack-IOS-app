import Combine
import Foundation

class AppState: ObservableObject {
    @Published var isRideActive = false
    @Published var currentUser: ConvoyUser? = nil
    @Published var currentRide: Ride? = nil
    @Published var liveRideState: RideStateUpdate? = nil

    // Persisted across launches — survives app kill/rebuild
    @Published var currentRideId: String? = nil {
        didSet {
            if let id = currentRideId {
                UserDefaults.standard.set(id, forKey: "currentRideId")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentRideId")
                currentRide = nil
            }
        }
    }

    @Published var inviteCode: String? = nil {
        didSet {
            if let code = inviteCode {
                UserDefaults.standard.set(code, forKey: "inviteCode")
            } else {
                UserDefaults.standard.removeObject(forKey: "inviteCode")
            }
        }
    }

    init() {
        currentRideId = UserDefaults.standard.string(forKey: "currentRideId")
        inviteCode    = UserDefaults.standard.string(forKey: "inviteCode")
    }
}
