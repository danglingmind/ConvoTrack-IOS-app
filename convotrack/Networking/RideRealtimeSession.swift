import SwiftUI
import Combine

/// The single, long-lived owner of the ride's realtime connection.
///
/// Created once in `MainTabView` (beside `AppState`) and injected via `.environmentObject`, so it
/// lives ABOVE both `RideLobbyView` and `RideNavigationView` and survives the lobby→navigation
/// push. It is the **sole subscriber** to `SocketClient`'s callbacks (which are single-slot) —
/// downstream fan-out to the two screens happens through `@Published` state, which SwiftUI/Combine
/// observe with any number of subscribers. This removes the old fragility where the two view models
/// clobbered each other's socket callbacks and navigation only recovered from a reconnect *by
/// accident* (because a lingering lobby VM happened to re-join the room).
///
/// Responsibilities centralized here for the ride's full lifetime:
///  - connect / reconnect→rejoin (`onConnect → joinRoom`)
///  - a single presence heartbeat (so a stationary rider doesn't false-drop to offline)
///  - authoritative roster + presence + connection state
///  - the raw `ride:state_update` stream and transient events (split / regroup / emergency)
@MainActor
final class RideRealtimeSession: ObservableObject {
    enum ConnectionState: Equatable { case connected, reconnecting, disconnected }

    // MARK: Shared state — both screens bind directly
    // Optimistic default so a fresh entry / cold connect shows no "reconnecting" banner. Socket
    // lifecycle events flip it to .reconnecting only when a real drop or failed attempt occurs.
    @Published private(set) var connectionState: ConnectionState = .connected
    @Published private(set) var participants: [RideParticipant] = []   // roster: names/avatars/status
    @Published private(set) var onlineUserIds: Set<String> = []        // authoritative presence
    @Published private(set) var leaderId: String = ""
    @Published private(set) var rideStatus: String = "LOBBY"
    @Published private(set) var liveState: RideStateUpdate? = nil       // latest ride:state_update

    // MARK: Transient events — screens react via .sink / .onChange
    @Published private(set) var splitActive: Bool = false
    @Published private(set) var latestRegroup: RegroupEvent? = nil
    @Published private(set) var latestRegroupResolvedId: String? = nil
    @Published private(set) var latestEmergency: EmergencyEvent? = nil
    @Published private(set) var rideUpdated: RideUpdatedEvent? = nil
    @Published private(set) var wasRemoved: Bool = false

    private var rideId = ""
    private var myUserId = ""
    private var isRunning = false
    private var heartbeatTimer: Timer?

    // MARK: - Lifecycle

    /// Start (or resume) the realtime session for a ride. Idempotent: calling it again for the
    /// same ride while already running just ensures room membership and returns — so navigation can
    /// safely call it after the lobby without resetting the live roster. Called with a different
    /// ride, it tears the previous one down first.
    func start(rideId: String, token: String, myUserId: String,
               seedParticipants: [RideParticipant], leaderId: String) {
        if isRunning && self.rideId == rideId {
            joinRoom()
            return
        }
        if isRunning { stop() }

        self.rideId = rideId
        self.myUserId = myUserId
        self.participants = seedParticipants
        self.leaderId = leaderId
        self.isRunning = true

        wireCallbacks()

        let socket = SocketClient.shared
        if socket.isConnected {
            connectionState = .connected
            joinRoom()
        } else {
            // Stay optimistic (.connected) through the cold connect; onConnect confirms, and a
            // failed attempt surfaces via onReconnecting/onDisconnect → .reconnecting.
            socket.connect(token: token)
        }

        startHeartbeat()
    }

    /// Tear the session down on genuine ride exit (left lobby / removed / ride ended). NOT called on
    /// the lobby→navigation push, so the connection survives the whole ride.
    func stop() {
        stopHeartbeat()

        let socket = SocketClient.shared
        socket.onConnect = nil
        socket.onDisconnect = nil
        socket.onReconnecting = nil
        socket.onStateUpdate = nil
        socket.onLobbyRoster = nil
        socket.onParticipantJoined = nil
        socket.onParticipantLeft = nil
        socket.onParticipantRemoved = nil
        socket.onPresence = nil
        socket.onParticipantReady = nil
        socket.onRideUpdated = nil
        socket.onSplitDetected = nil
        socket.onSplitResolved = nil
        socket.onRegroupStarted = nil
        socket.onRegroupResolved = nil
        socket.onEmergencyStarted = nil
        socket.disconnect()

        isRunning = false
        rideId = ""
        myUserId = ""
        connectionState = .disconnected
        participants = []
        onlineUserIds = []
        leaderId = ""
        rideStatus = "LOBBY"
        liveState = nil
        splitActive = false
        latestRegroup = nil
        latestRegroupResolvedId = nil
        latestEmergency = nil
        rideUpdated = nil
        wasRemoved = false
    }

    deinit { heartbeatTimer?.invalidate() }

    // MARK: - Room

    private func joinRoom() {
        guard !rideId.isEmpty else { return }
        SocketClient.shared.joinRoom(rideId: rideId)
        // Optimistic self-presence so my own dot isn't grey until the first ride:presence snapshot;
        // the snapshot then becomes authoritative.
        if !myUserId.isEmpty { onlineUserIds.insert(myUserId) }
    }

    // MARK: - Presence heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let rideId = self.rideId
        // Emit now, then every 5s. Timers don't fire while the app is suspended, so
        // backgrounding / locking / killing stops heartbeats and the server's TTL lapses us to
        // offline. Unlike the old lobby-only heartbeat, this runs for the WHOLE ride, so a
        // stationary rider in navigation (who emits no movement-driven location updates) stays
        // online. Capture rideId locally and only touch the global SocketClient so the timer
        // closure never reaches back into main-actor state.
        SocketClient.shared.emitHeartbeat(rideId: rideId)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            SocketClient.shared.emitHeartbeat(rideId: rideId)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Callback wiring (single subscriber)

    private func wireCallbacks() {
        let socket = SocketClient.shared

        socket.onConnect = { [weak self] in
            guard let self else { return }
            self.connectionState = .connected
            self.joinRoom()   // re-join on every (re)connect → server re-sends roster + last locations
        }
        socket.onDisconnect = { [weak self] in self?.connectionState = .reconnecting }
        socket.onReconnecting = { [weak self] in self?.connectionState = .reconnecting }

        socket.onStateUpdate = { [weak self] update in
            guard let self else { return }
            self.rideStatus = update.status
            self.liveState = update
        }

        // Authoritative membership snapshot — the server sends this on every room join. Apply
        // unconditionally so any delta missed during the connect window is reconciled.
        socket.onLobbyRoster = { [weak self] participants, leaderId in
            guard let self else { return }
            self.participants = participants
            if !leaderId.isEmpty { self.leaderId = leaderId }
        }
        socket.onParticipantJoined = { [weak self] participant in
            guard let self else { return }
            if !self.participants.contains(where: { $0.userId == participant.userId }) {
                self.participants.append(participant)
            }
            self.onlineUserIds.insert(participant.userId)
        }
        socket.onParticipantLeft = { [weak self] userId in
            self?.participants.removeAll { $0.userId == userId }
        }
        socket.onParticipantRemoved = { [weak self] userId in
            guard let self else { return }
            self.participants.removeAll { $0.userId == userId }
            if userId == self.myUserId { self.wasRemoved = true }
        }
        // The ONLY driver of the green presence dot (heartbeat/TTL snapshot from the server), so a
        // lingering socket can never falsely show a locked/closed device as online.
        socket.onPresence = { [weak self] online in
            self?.onlineUserIds = Set(online)
        }
        socket.onParticipantReady = { [weak self] userId in
            self?.updateParticipantStatus(userId: userId, status: "READY")
        }
        socket.onRideUpdated = { [weak self] event in self?.rideUpdated = event }

        socket.onSplitDetected = { [weak self] _ in self?.splitActive = true }
        socket.onSplitResolved = { [weak self] in self?.splitActive = false }
        socket.onRegroupStarted = { [weak self] event in self?.latestRegroup = event }
        socket.onRegroupResolved = { [weak self] id in self?.latestRegroupResolvedId = id }
        socket.onEmergencyStarted = { [weak self] event in self?.latestEmergency = event }
    }

    private func updateParticipantStatus(userId: String, status: String) {
        guard let idx = participants.firstIndex(where: { $0.userId == userId }) else { return }
        let old = participants[idx]
        participants[idx] = RideParticipant(
            userId: old.userId, name: old.name, avatarUrl: old.avatarUrl,
            status: status, isLeader: old.isLeader, joinedAt: old.joinedAt
        )
    }
}

// MARK: - Connection banner

/// Slim "reconnecting" strip. Callers gate it on `connectionState == .reconnecting`, so it takes no
/// layout space while the connection is healthy (and doesn't flash on a cold connect or teardown).
struct ConnectionBanner: View {
    let state: RideRealtimeSession.ConnectionState

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.errorColor)
            Text("RECONNECTING…")
                .font(.labelCaps)
                .foregroundColor(Color.errorColor)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.errorContainer.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}
