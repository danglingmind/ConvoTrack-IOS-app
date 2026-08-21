import Foundation
import SocketIO

final class SocketClient {
    static let shared = SocketClient()

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    // MARK: - Event Callbacks (set by RideRealtimeSession — the single subscriber)
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?      // transport dropped; library will auto-reconnect
    var onReconnecting: (() -> Void)?    // a reconnect attempt is in flight
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
    var onEmergencyResolved: ((String) -> Void)?   // emergencyId
    var onRegroupStarted: ((RegroupEvent) -> Void)?
    var onRegroupResolved: ((String) -> Void)?   // regroupId
    var onRideUpdated: ((RideUpdatedEvent) -> Void)?
    var onRideDeleted: (() -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {}

    // MARK: - Lifecycle

    func connect(token: String) {
        // Idempotent, and it has to be: `RideRealtimeSession.start()` is called from both the
        // lobby's and the navigation screen's `.task`, and it connects whenever the socket isn't
        // yet `.connected` — which includes the window where it is still `.connecting`.
        //
        // Replacing `manager` without disconnecting the old one left a ghost behind. Configured
        // with `.reconnects(true)` and `.reconnectAttempts(-1)`, an abandoned manager retries
        // FOREVER, and its handlers still call into this singleton's closures — so it kept firing
        // `.reconnectAttempt` into `onReconnecting` every few seconds. That is what pinned the
        // "reconnecting" banner on while the live socket was perfectly healthy, and why clearing
        // the state on a timer never held: the ghost simply raised it again.
        if socket?.status == .connected { return }
        disconnect()

        manager = SocketManager(socketURL: AppURLs.backendBaseURL, config: [
            .log(false),
            .compress,
            // Mobile links drop constantly (tunnels, lifts, cell↔wifi handoff). Reconnect
            // forever with a capped, jittered backoff instead of relying on library defaults,
            // and pin to websockets so a flaky link can't thrash between transports.
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWait(2),
            .reconnectWaitMax(15),
            .randomizationFactor(0.5),
            .forceWebsockets(true),
        ])
        socket = manager?.defaultSocket
        registerHandlers()
        // connect(withPayload:) sends the dict as socket.io CONNECT packet auth,
        // which maps to socket.handshake.auth on the server — required by Clerk middleware.
        socket?.connect(withPayload: ["token": token])
    }

    func disconnect() {
        // Handlers first: a socket that is going away must not be able to call back into these
        // closures on its way out (or from a retry already in flight), otherwise it can still
        // report a disconnect/reconnect for a session that has moved on.
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
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

    /// Clear an open emergency. The server authorizes it (creator or leader only) and broadcasts
    /// `ride:emergency_resolved` so the pin + siren stop on every device.
    func emitEmergencyDismiss(rideId: String, emergencyId: String) {
        socket?.emit("ride:emergency_dismiss", ["rideId": rideId, "emergencyId": emergencyId])
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

        // Surface the connection lifecycle so the session can drive reconnect→rejoin and a
        // "reconnecting" banner. `.disconnect` also fires on our own disconnect(), but by then
        // the session has already nil'd these callbacks, so it won't misreport a manual teardown.
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onDisconnect?() }
        }
        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onReconnecting?() }
        }
        socket.on(clientEvent: .reconnectAttempt) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onReconnecting?() }
        }
        // Authoritative recovery signal. `.connect` doesn't reliably re-fire on an auto-reconnect,
        // which left the "reconnecting" banner stuck on forever; the manager's `.statusChange`
        // always reports the real transition, so a return to `.connected` clears it every time.
        // (Intentionally NOT mapping `.error` → reconnecting: it fires for non-fatal errors while
        // still connected and would flip the banner on with nothing to turn it back off.)
        socket.on(clientEvent: .statusChange) { [weak self] data, _ in
            guard let self, (data.first as? SocketIOStatus) == .connected else { return }
            DispatchQueue.main.async { self.onConnect?() }
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

        socket.on("ride:deleted") { [weak self] _, _ in
            DispatchQueue.main.async { self?.onRideDeleted?() }
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

        socket.on("ride:emergency_resolved") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let emergencyId = dict["emergencyId"] as? String else { return }
            DispatchQueue.main.async { self?.onEmergencyResolved?(emergencyId) }
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
