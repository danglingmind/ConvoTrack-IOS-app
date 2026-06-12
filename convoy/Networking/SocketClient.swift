import Foundation
import SocketIO

final class SocketClient {
    static let shared = SocketClient()

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    // MARK: - Event Callbacks (set by views)
    var onStateUpdate: ((RideStateUpdate) -> Void)?
    var onParticipantJoined: ((RideParticipant) -> Void)?
    var onParticipantLeft: ((String) -> Void)?
    var onParticipantReady: ((String) -> Void)?
    var onSplitDetected: (([String: Any]) -> Void)?
    var onSplitResolved: (() -> Void)?
    var onEmergencyStarted: (([String: Any]) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {}

    // MARK: - Lifecycle

    func connect(token: String) {
        let url = URL(string: "https://convoy-backend-hx3c.onrender.com")!
        // token passes via socket.auth as expected by backend Clerk middleware
        manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .connectParams(["auth": ["token": token]])
        ])
        socket = manager?.defaultSocket
        registerHandlers()
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        manager = nil
    }

    var isConnected: Bool {
        socket?.status == .connected
    }

    // MARK: - Room

    func joinRoom(rideId: String) {
        socket?.emit("ride:join", ["rideId": rideId])
    }

    // MARK: - Emit: Location

    func emitLocationUpdate(rideId: String, lat: Double, lng: Double, speed: Double, heading: Double, battery: Double, signalStrength: String) {
        let payload: [String: Any] = [
            "rideId": rideId,
            "lat": lat,
            "lng": lng,
            "speed": speed,
            "heading": heading,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "battery": battery,
            "signalStrength": signalStrength
        ]
        socket?.emit("ride:location_update", payload)
    }

    // MARK: - Emit: Ready (with ack)

    func emitReady(rideId: String, completion: @escaping (Bool) -> Void) {
        socket?.emitWithAck("ride:ready", ["rideId": rideId]).timingOut(after: 5) { data in
            completion(!data.isEmpty)
        }
    }

    // MARK: - Emit: Regroup / Emergency

    func emitRegroup(rideId: String, type: String, lat: Double, lng: Double) {
        socket?.emit("ride:regroup", ["rideId": rideId, "type": type, "lat": lat, "lng": lng])
    }

    func emitEmergency(rideId: String, lat: Double, lng: Double, message: String) {
        socket?.emit("ride:emergency", ["rideId": rideId, "lat": lat, "lng": lng, "message": message])
    }

    // MARK: - Incoming Event Handlers

    private func registerHandlers() {
        guard let socket else { return }

        socket.on("ride:state_update") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let update = try? self.decoder.decode(RideStateUpdate.self, from: json) else { return }
            DispatchQueue.main.async { self.onStateUpdate?(update) }
        }

        socket.on("ride:participant_joined") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let participant = try? self.decoder.decode(RideParticipant.self, from: json) else { return }
            DispatchQueue.main.async { self.onParticipantJoined?(participant) }
        }

        socket.on("ride:participant_left") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["userId"] as? String else { return }
            DispatchQueue.main.async { self?.onParticipantLeft?(userId) }
        }

        socket.on("ride:participant_ready") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["userId"] as? String else { return }
            DispatchQueue.main.async { self?.onParticipantReady?(userId) }
        }

        socket.on("ride:split_detected") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            DispatchQueue.main.async { self?.onSplitDetected?(dict) }
        }

        socket.on("ride:split_resolved") { [weak self] _, _ in
            DispatchQueue.main.async { self?.onSplitResolved?() }
        }

        socket.on("ride:emergency_started") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            DispatchQueue.main.async { self?.onEmergencyStarted?(dict) }
        }
    }
}
