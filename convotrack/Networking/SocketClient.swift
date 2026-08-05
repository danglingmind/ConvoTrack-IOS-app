import Foundation
import SocketIO

final class SocketClient {
    static let shared = SocketClient()

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    // MARK: - Event Callbacks (set by views)
    var onConnect: (() -> Void)?
    var onStateUpdate: ((RideStateUpdate) -> Void)?
    var onParticipantJoined: ((RideParticipant) -> Void)?
    var onParticipantLeft: ((String) -> Void)?
    var onParticipantRemoved: ((String) -> Void)?   // userId removed by leader
    var onParticipantOffline: ((String) -> Void)?
    var onParticipantReady: ((String) -> Void)?
    var onPresence: (([String]) -> Void)?   // authoritative online userIds (heartbeat-based)
    var onLobbyRoster: (([RideParticipant], String) -> Void)?
    var onSplitDetected: (([String: Any]) -> Void)?
    var onSplitResolved: (() -> Void)?
    var onEmergencyStarted: ((EmergencyEvent) -> Void)?
    var onRegroupStarted: ((RegroupEvent) -> Void)?
    var onRegroupResolved: ((String) -> Void)?   // regroupId
    var onRideUpdated: ((RideUpdatedEvent) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {}

    // MARK: - Lifecycle

    func connect(token: String) {
        manager = SocketManager(socketURL: AppURLs.backendBaseURL, config: [
            .log(false),
            .compress,
        ])
        socket = manager?.defaultSocket
        registerHandlers()
        // connect(withPayload:) sends the dict as socket.io CONNECT packet auth,
        // which maps to socket.handshake.auth on the server — required by Clerk middleware.
        socket?.connect(withPayload: ["token": token])
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

    func emitRegroup(rideId: String, type: String, lat: Double, lng: Double,
                     completion: @escaping (String?) -> Void) {
        let payload: [String: Any] = ["rideId": rideId, "type": type, "lat": lat, "lng": lng]
        socket?.emitWithAck("ride:regroup", payload).timingOut(after: 5) { data in
            guard let dict = data.first as? [String: Any],
                  let ok = dict["ok"] as? Bool, ok,
                  let regroupId = dict["regroupId"] as? String else {
                completion(nil)
                return
            }
            completion(regroupId)
        }
    }

    func emitEmergency(rideId: String, lat: Double, lng: Double, message: String) {
        socket?.emit("ride:emergency", ["rideId": rideId, "lat": lat, "lng": lng, "message": message])
    }

    func emitRegroupArrived(rideId: String, regroupId: String) {
        socket?.emit("ride:regroup_arrived", ["rideId": rideId, "regroupId": regroupId])
    }

    // MARK: - Emit: Presence heartbeat

    /// Periodic liveness ping. The server keeps the user in the ride's online set while these
    /// arrive within its TTL; stopping (background/lock/kill) lets them lapse to offline.
    func emitHeartbeat(rideId: String) {
        socket?.emit("ride:heartbeat", ["rideId": rideId])
    }

    // MARK: - Incoming Event Handlers

    private func registerHandlers() {
        guard let socket else { return }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onConnect?() }
        }

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

        socket.on("ride:participant_removed") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["userId"] as? String else { return }
            DispatchQueue.main.async { self?.onParticipantRemoved?(userId) }
        }

        socket.on("ride:participant_offline") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["userId"] as? String else { return }
            DispatchQueue.main.async { self?.onParticipantOffline?(userId) }
        }

        socket.on("ride:participant_ready") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let userId = dict["userId"] as? String else { return }
            DispatchQueue.main.async { self?.onParticipantReady?(userId) }
        }

        socket.on("ride:presence") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let online = dict["online"] as? [String] else { return }
            DispatchQueue.main.async { self?.onPresence?(online) }
        }

        socket.on("ride:lobby_roster") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let leaderId = dict["leaderId"] as? String,
                  let rawList = dict["participants"] as? [[String: Any]],
                  let json = try? JSONSerialization.data(withJSONObject: rawList),
                  let participants = try? self.decoder.decode([RideParticipant].self, from: json) else { return }
            DispatchQueue.main.async { self.onLobbyRoster?(participants, leaderId) }
        }

        socket.on("ride:split_detected") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            DispatchQueue.main.async { self?.onSplitDetected?(dict) }
        }

        socket.on("ride:split_resolved") { [weak self] _, _ in
            DispatchQueue.main.async { self?.onSplitResolved?() }
        }

        socket.on("ride:emergency_started") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let event = try? self.decoder.decode(EmergencyEvent.self, from: json) else { return }
            DispatchQueue.main.async { self.onEmergencyStarted?(event) }
        }

        socket.on("ride:regroup_started") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let event = try? self.decoder.decode(RegroupEvent.self, from: json) else { return }
            DispatchQueue.main.async { self.onRegroupStarted?(event) }
        }

        socket.on("ride:regroup_resolved") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let regroupId = dict["regroupId"] as? String else { return }
            DispatchQueue.main.async { self?.onRegroupResolved?(regroupId) }
        }

        socket.on("ride:updated") { [weak self] data, _ in
            guard let self,
                  let dict = data.first as? [String: Any],
                  let json = try? JSONSerialization.data(withJSONObject: dict),
                  let event = try? self.decoder.decode(RideUpdatedEvent.self, from: json) else { return }
            DispatchQueue.main.async { self.onRideUpdated?(event) }
        }
    }
}
