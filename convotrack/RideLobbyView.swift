import SwiftUI
import CoreLocation
import ClerkKit
import Combine

// MARK: - ViewModel

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var participants: [RideParticipant] = []
    @Published var onlineUserIds: Set<String> = []
    @Published var myStatus = "WAITING"   // optimistic local ready state
    @Published var isStarting = false
    @Published var socketConnected = false
    @Published var startError: String? = nil
    @Published var removingUserId: String? = nil   // in-flight removal target
    @Published var removeError: String? = nil

    var rideId = ""
    var myUserId = ""
    var leaderId = ""

    var amILeader: Bool { !myUserId.isEmpty && myUserId == leaderId }
    var onRideUpdated: ((RideUpdatedEvent) -> Void)?
    // Fired when the ride transitions LOBBY → ACTIVE (leader started it).
    // Lets non-leader riders auto-navigate into RideNavigationView.
    var onRideStarted: (() -> Void)?
    // Fired when *this* rider is removed from the ride by the leader.
    var onRemovedFromRide: (() -> Void)?

    // Leader can start when alone OR when all non-leaders have readied up
    var canStart: Bool {
        guard amILeader else { return false }
        let others = participants.filter { !$0.isLeader }
        return others.isEmpty || others.allSatisfy { $0.status == "READY" }
    }

    func setup(rideId: String, token: String) {
        let socket = SocketClient.shared
        if !socket.isConnected {
            socket.connect(token: token)
        }

        // state_update carries LiveParticipant (GPS/progress) — the lobby ignores the
        // telemetry payload, but uses it to detect the LOBBY → ACTIVE transition so
        // non-leader riders auto-advance when the leader starts the ride.
        socket.onStateUpdate = { [weak self] update in
            guard let self, update.status == "ACTIVE" else { return }
            self.onRideStarted?()
        }

        socket.onLobbyRoster = { [weak self] participants, leaderId in
            guard let self else { return }
            // Authoritative membership snapshot — the server sends this on every room join, so
            // apply it UNCONDITIONALLY. This reconciles any live delta (a rider joining or marking
            // ready) that was missed during the socket-connect window — the root cause of the
            // leader being stuck on WAITING until a manual reopen. Safe because: the local user's
            // optimistic ready is overlaid via myStatus at render, and every other rider's status
            // comes straight from this DB-backed snapshot (ready is persisted before it's sent).
            // Presence (green dot) remains separate (ride:presence).
            self.participants = participants
            if !leaderId.isEmpty { self.leaderId = leaderId }
        }

        socket.onParticipantJoined = { [weak self] participant in
            guard let self else { return }
            if !self.participants.contains(where: { $0.userId == participant.userId }) {
                self.participants.append(participant)
            }
            // Optimistic: a just-joined rider is online now; the next ride:presence snapshot
            // (authoritative) reconciles it. Avoids a grey flash before the first snapshot.
            self.onlineUserIds.insert(participant.userId)
        }

        socket.onParticipantLeft = { [weak self] userId in
            self?.participants.removeAll { $0.userId == userId }
        }

        socket.onParticipantRemoved = { [weak self] userId in
            guard let self else { return }
            self.participants.removeAll { $0.userId == userId }
            self.removingUserId = nil
            // If I'm the one removed, exit the ride.
            if userId == self.myUserId { self.onRemovedFromRide?() }
        }

        // Authoritative online set — heartbeat/TTL-based snapshot from the server. This is the
        // ONLY thing that drives the green presence dot, so a lingering socket / roster
        // membership can never falsely show a locked or closed device as online.
        socket.onPresence = { [weak self] online in
            self?.onlineUserIds = Set(online)
        }

        socket.onParticipantReady = { [weak self] userId in
            guard let self else { return }
            self.updateParticipantStatus(userId: userId, status: "READY")
            if userId == self.myUserId { self.myStatus = "READY" }
        }

        socket.onRideUpdated = { [weak self] event in
            self?.onRideUpdated?(event)
        }

        // Join the room once the socket is actually connected, rather than racing a
        // fixed timer. Covers both a fresh connect and a reused (already-open) socket.
        socket.onConnect = { [weak self] in
            self?.joinRoom(rideId: rideId)
        }
        if socket.isConnected {
            joinRoom(rideId: rideId)
        }

        startHeartbeat(rideId: rideId)
    }

    private func joinRoom(rideId: String) {
        SocketClient.shared.joinRoom(rideId: rideId)
        socketConnected = true
        // Optimistic self-presence so my own dot isn't grey until the first ride:presence
        // snapshot lands; the snapshot then becomes authoritative.
        if !myUserId.isEmpty { onlineUserIds.insert(myUserId) }
    }

    // MARK: - Presence heartbeat

    private var heartbeatTimer: Timer?

    private func startHeartbeat(rideId: String) {
        heartbeatTimer?.invalidate()
        // Emit now, then every 8s. Timers don't fire while the app is suspended, so
        // backgrounding / locking / killing the app stops heartbeats and the server's TTL
        // lapses us to offline — no reliance on a (flaky) socket disconnect.
        SocketClient.shared.emitHeartbeat(rideId: rideId)
        // [weak self] + self-invalidate so the repeating timer can't outlive the VM and keep a
        // departed rider falsely "online" if a teardown path deallocs without calling disconnect().
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            SocketClient.shared.emitHeartbeat(rideId: rideId)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    func markReady(rideId: String) {
        guard myStatus != "READY" else { return }
        // Optimistic update
        myStatus = "READY"
        updateParticipantStatus(userId: myUserId, status: "READY")

        SocketClient.shared.emitReady(rideId: rideId) { [weak self] success in
            if !success {
                // Rollback on ack failure
                self?.myStatus = "WAITING"
                self?.updateParticipantStatus(userId: self?.myUserId ?? "", status: "WAITING")
            }
        }
    }

    func removeParticipant(userId: String) async {
        guard amILeader, userId != myUserId else { return }
        removingUserId = userId
        removeError = nil
        do {
            try await APIClient.shared.removeParticipant(rideId: rideId, userId: userId)
            // The ride:participant_removed broadcast (which the leader also receives)
            // performs the actual roster removal + clears removingUserId.
        } catch {
            removingUserId = nil
            removeError = (error as? APIClientError)?.localizedDescription
                ?? error.localizedDescription
        }
    }

    func startRide(rideId: String) async {
        isStarting = true
        startError = nil
        do {
            try await APIClient.shared.startRide(rideId)
        } catch let error as APIClientError {
            switch error {
            case .serverError(let msg) where msg.contains("RIDE_NOT_IN_LOBBY"):
                break  // ride is already ACTIVE — treat as success and navigate
            default:
                startError = error.localizedDescription
            }
        } catch {
            startError = error.localizedDescription
        }
        isStarting = false
    }

    func disconnect() {
        stopHeartbeat()
        // Clear the callbacks this VM registered on the shared client so a later reconnect /
        // screen reuse can't fire stale lobby closures (e.g. a spurious joinRoom or a
        // state handler bound to a dead VM).
        let socket = SocketClient.shared
        socket.onConnect = nil
        socket.onStateUpdate = nil
        socket.onLobbyRoster = nil
        socket.onParticipantJoined = nil
        socket.onParticipantLeft = nil
        socket.onParticipantRemoved = nil
        socket.onParticipantReady = nil
        socket.onPresence = nil
        socket.onRideUpdated = nil
        socket.disconnect()
        socketConnected = false
    }

    deinit { heartbeatTimer?.invalidate() }

    private func updateParticipantStatus(userId: String, status: String) {
        guard let idx = participants.firstIndex(where: { $0.userId == userId }) else { return }
        let old = participants[idx]
        participants[idx] = RideParticipant(
            userId: old.userId, name: old.name, avatarUrl: old.avatarUrl,
            status: status, isLeader: old.isLeader, joinedAt: old.joinedAt
        )
    }
}

// MARK: - RideLobbyView

struct RideLobbyView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LobbyViewModel()

    @State private var showShareSheet = false
    @State private var showQRModal = false
    @State private var showRiderDetail = false
    @State private var showNavigation = false
    @State private var showEditSheet = false
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraCommand: MapCameraCommand? = nil
    @State private var showStartError = false
    @State private var participantToManage: RideParticipant? = nil
    @State private var showRemovedAlert = false
    @State private var showRemoveError = false

    // MARK: - Derived

    private var rideTitle: String { appState.currentRide?.title ?? "Ride Lobby" }
    private var destinationName: String { appState.currentRide?.destinationName ?? "" }
    private var distanceKm: String {
        guard let d = appState.currentRide?.distanceMeters, d > 0 else { return "--" }
        return String(format: "%.0f", d / 1000)
    }
    private var inviteCode: String { appState.inviteCode ?? "" }

    private var deepLinkURL: URL? {
        guard !inviteCode.isEmpty else { return nil }
        return URL(string: AppURLs.joinLink(code: inviteCode))
    }

    private var shareItems: [Any] {
        guard let url = deepLinkURL else {
            return ["Join my ConvoTrack ride!"]
        }
        // HTTPS Universal Link: tappable in every messaging app, opens the app if
        // installed and falls back to a web page + store links otherwise.
        return ["Join my ConvoTrack ride!", url]
    }

    private var myClerkName: String? {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? clerk.user?.username : name
    }

    /// The leader may edit the ride whenever the Start button is available (leader,
    /// ride not yet ACTIVE). Kept in lockstep with the `bottomBar` Start-button gate
    /// so the pencil never disappears while the Start button is showing. Leadership is
    /// read from both the reactive Clerk identity AND the VM's cached `amILeader` — the
    /// former survives app relaunch before the cache is seeded, the latter survives a
    /// transient render where `clerk.user` reads nil. Requires `currentRide` since
    /// `EditRideView` needs a ride to edit.
    private var canEditRide: Bool {
        guard let ride = appState.currentRide, ride.status != "ACTIVE" else { return false }
        if vm.amILeader { return true }
        if let uid = clerk.user?.id, !uid.isEmpty, uid == ride.leaderId { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    mapSection
                    rosterSection
                    Color.clear.frame(height: 120)
                }
            }
            .ignoresSafeArea(edges: .top)

            VStack {
                HStack(spacing: 12) {
                    Button(action: {
                        vm.disconnect()
                        dismiss()
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Text(rideTitle)
                        .font(.bodyLg)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                    Spacer()
                    if canEditRide {
                        Button(action: { showEditSheet = true }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }

            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showNavigation) {
            RideNavigationView(rideId: vm.rideId)
        }
        .background(
            ShareSheetPresenter(
                isPresented: $showShareSheet,
                items: shareItems
            )
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showRiderDetail) { RiderDetailDrawer() }
        .sheet(isPresented: $showQRModal) { QRCodeModal(inviteCode: inviteCode) }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            Task { await refreshAfterEdit() }
        }) {
            if let ride = appState.currentRide {
                EditRideView(ride: ride)
                    .environmentObject(appState)
                    .environmentObject(membershipStore)
            }
        }
        .sheet(item: $participantToManage) { participant in
            RemoveRiderSheet(
                participant: participant,
                isRemoving: vm.removingUserId == participant.userId
            ) {
                Task {
                    await vm.removeParticipant(userId: participant.userId)
                    participantToManage = nil
                }
            }
        }
        .alert("Couldn't Start Ride", isPresented: $showStartError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.startError ?? "An error occurred.")
        }
        .onChange(of: vm.startError) { _, err in
            if err != nil { showStartError = true }
        }
        .alert("Couldn't Remove Rider", isPresented: $showRemoveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.removeError ?? "An error occurred.")
        }
        .onChange(of: vm.removeError) { _, err in
            if err != nil { showRemoveError = true }
        }
        .alert("Removed From Ride", isPresented: $showRemovedAlert) {
            Button("OK", role: .cancel) {
                appState.currentRideId = nil   // also clears currentRide
                appState.inviteCode = nil
                dismiss()
            }
        } message: {
            Text("The ride leader removed you from this ride.")
        }
        .task { await loadRideAndConnect() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            GoogleMapView(
                routeCoords:   routeCoordinates,
                stopCoords:    lobbyStopCoords,
                pins:          lobbyMapPins,
                cameraCommand: cameraCommand,
                isInteractive: false
            )
            .frame(maxWidth: .infinity, minHeight: 420)

            LinearGradient(
                colors: [Color.black.opacity(0.45), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            LinearGradient(
                colors: [Color.surfaceDim, Color.surfaceDim.opacity(0.55), .clear],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: 420)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FloatingStatPill(label: "DISTANCE", value: distanceKm, unit: "km")
                    FloatingStatPill(label: "RIDERS", value: "\(vm.participants.count)", unit: nil)
                    FloatingStatPill(
                        label: "STATUS",
                        value: vm.canStart ? "Ready" : "Waiting",
                        unit: nil,
                        dotColor: vm.canStart ? Color.primaryFixed : Color.secondaryFixed
                    )
                    if !inviteCode.isEmpty {
                        FloatingStatPill(label: "CODE", value: inviteCode, unit: nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 420)
    }

    private var lobbyMapPins: [MapPin] {
        let waypoints = appState.currentRide?.waypoints ?? []
        var pins: [MapPin] = []
        if let wp = waypoints.first(where: { $0.type == "START" }) {
            pins.append(MapPin(id: "start", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .lobbyStart))
        }
        for wp in waypoints.filter({ $0.type == "WAYPOINT" }) {
            pins.append(MapPin(id: "wp_\(wp.order)", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .waypoint(name: wp.name)))
        }
        if let wp = waypoints.first(where: { $0.type == "DESTINATION" }) {
            pins.append(MapPin(id: "dest", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .destination(name: wp.name)))
        }
        return pins
    }

    private var lobbyStopCoords: [CLLocationCoordinate2D] {
        guard let ride = appState.currentRide else { return [] }
        return ride.waypoints.sorted { $0.order < $1.order }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    // MARK: - Roster Section

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SQUAD ROSTER")
                    .font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(4)
                Spacer()
                if vm.socketConnected {
                    HStack(spacing: 4) {
                        Circle().fill(Color.primaryFixed).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed).tracking(2)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    ShareButton(icon: "link") { showShareSheet = true }
                    ShareButton(icon: "qrcode") { showQRModal = true }
                }
            }

            if vm.participants.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().tint(Color.primaryFixed)
                    Text("Loading roster...")
                        .font(.bodyMd).foregroundColor(Color.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(vm.participants, id: \.userId) { participant in
                        let isMe = participant.userId == vm.myUserId
                        let name = isMe ? (myClerkName ?? participant.name) : participant.name
                        let status = isMe ? vm.myStatus : participant.status
                        // The leader can tap any non-leader rider to open the
                        // management sheet (remove from ride).
                        let canManage = vm.amILeader && participant.userId != vm.leaderId
                        let row = ParticipantRiderRow(participant: participant, nameOverride: name, statusOverride: status, isOnline: vm.onlineUserIds.contains(participant.userId))
                        if canManage {
                            Button { participantToManage = participant } label: { row }
                                .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.surfaceDim.opacity(0), Color.surfaceDim], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)

            if appState.currentRide?.status == "ACTIVE" {
                resumeNavigationButton
            } else if vm.amILeader {
                leaderStartButton
            } else {
                riderReadyButton
            }
        }
    }

    private var resumeNavigationButton: some View {
        Button(action: { showNavigation = true }) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("RESUME NAVIGATION").font(.headlineMd).tracking(-0.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.primaryFixed)
            .foregroundColor(Color.onPrimaryFixed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.primaryFixed.opacity(0.3), radius: 20)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 60)
        .background(Color.surfaceDim)
    }

    private var leaderStartButton: some View {
        Button(action: {
            Task {
                await vm.startRide(rideId: vm.rideId)
                if vm.startError == nil {
                    // Mark ride as ACTIVE locally so resuming correctly shows RESUME NAVIGATION
                    if let ride = appState.currentRide {
                        appState.currentRide = Ride(
                            id: ride.id, title: ride.title, status: "ACTIVE",
                            leaderId: ride.leaderId, inviteCode: ride.inviteCode,
                            destinationName: ride.destinationName,
                            destinationLat: ride.destinationLat, destinationLng: ride.destinationLng,
                            distanceMeters: ride.distanceMeters,
                            estimatedDurationSeconds: ride.estimatedDurationSeconds,
                            maxAllowedParticipants: ride.maxAllowedParticipants,
                            startedAt: ride.startedAt, endedAt: ride.endedAt,
                            createdAt: ride.createdAt,
                            waypoints: ride.waypoints, participants: ride.participants
                        )
                    }
                    showNavigation = true
                }
            }
        }) {
            HStack(spacing: 12) {
                if vm.isStarting {
                    ProgressView().tint(Color.onPrimaryFixed)
                    Text("STARTING...").font(.headlineMd).tracking(-0.5)
                } else if vm.canStart {
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                    Text("START RIDE").font(.headlineMd).tracking(-0.5)
                } else {
                    Image(systemName: "clock").font(.system(size: 20))
                    Text("WAITING FOR RIDERS").font(.headlineMd).tracking(-0.5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(vm.canStart ? Color.primaryFixed : Color.surfaceContainerHigh)
            .foregroundColor(vm.canStart ? Color.onPrimaryFixed : Color.onSurfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: vm.canStart ? Color.primaryFixed.opacity(0.3) : .clear, radius: 20)
        }
        .disabled(!vm.canStart || vm.isStarting)
        .padding(.horizontal, 20)
        .padding(.bottom, 60)
        .background(Color.surfaceDim)
    }

    private var riderReadyButton: some View {
        Button(action: {
            vm.markReady(rideId: vm.rideId)
        }) {
            HStack(spacing: 12) {
                Image(systemName: vm.myStatus == "READY" ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                Text(vm.myStatus == "READY" ? "YOU'RE READY" : "MARK AS READY")
                    .font(.headlineMd).tracking(-0.5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(vm.myStatus == "READY" ? Color.surfaceContainerHigh : Color.primaryFixed)
            .foregroundColor(vm.myStatus == "READY" ? Color.primaryFixed : Color.onPrimaryFixed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(vm.myStatus == "READY" ? Color.primaryFixed : .clear, lineWidth: 1.5)
            )
        }
        .disabled(vm.myStatus == "READY")
        .padding(.horizontal, 20)
        .padding(.bottom, 60)
        .background(Color.surfaceDim)
    }

    // MARK: - Load + Connect

    private func loadRideAndConnect() async {
        guard let rideId = appState.currentRideId else { return }
        vm.rideId = rideId

        // Always fetch fresh — ride status may have changed since last visit (e.g. LOBBY → ACTIVE)
        if let ride = try? await APIClient.shared.getRide(rideId) {
            appState.currentRide = ride
        }

        if let ride = appState.currentRide {
            vm.myUserId = clerk.user?.id ?? ""
            vm.leaderId = ride.leaderId
            vm.participants = ride.participants
            // Sync own initial status from server
            if let me = ride.participants.first(where: { $0.userId == vm.myUserId }) {
                vm.myStatus = me.status
            }
        }

        if let waypoints = appState.currentRide?.waypoints {
            await calculateRoute(from: waypoints)
        }

        vm.onRideUpdated = { [appState] event in
            guard let existing = appState.currentRide else { return }
            appState.currentRide = Ride(
                id: existing.id,
                title: event.title,
                status: existing.status,
                leaderId: existing.leaderId,
                inviteCode: existing.inviteCode,
                destinationName: event.destinationName,
                destinationLat: event.destinationLat,
                destinationLng: event.destinationLng,
                distanceMeters: event.distanceMeters,
                estimatedDurationSeconds: event.estimatedDurationSeconds,
                maxAllowedParticipants: event.maxAllowedParticipants,
                startedAt: existing.startedAt,
                endedAt: existing.endedAt,
                createdAt: existing.createdAt,
                waypoints: event.waypoints,
                participants: existing.participants
            )
            Task { await calculateRoute(from: event.waypoints) }
        }

        // Ride is/became ACTIVE: reflect the status locally so the bottom bar shows
        // RESUME NAVIGATION. Do NOT auto-navigate — the rider stays on the lobby and taps
        // RESUME to enter navigation. (The leader's own Start button navigates directly.)
        vm.onRideStarted = { [appState] in
            if let ride = appState.currentRide, ride.status != "ACTIVE" {
                appState.currentRide = ride.with(status: "ACTIVE")
            }
        }

        // I was removed by the leader — tear down the socket and surface an alert.
        vm.onRemovedFromRide = {
            vm.disconnect()
            showRemovedAlert = true
        }

        if let token = try? await Clerk.shared.auth.getToken() {
            vm.setup(rideId: rideId, token: token)
        }
    }

    @MainActor
    private func refreshAfterEdit() async {
        guard let rideId = appState.currentRideId else { return }
        if let ride = try? await APIClient.shared.getRide(rideId) {
            appState.currentRide = ride
            await calculateRoute(from: ride.waypoints)
        }
    }

    @MainActor
    private func calculateRoute(from waypoints: [Waypoint]) async {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }

        var allCoords: [CLLocationCoordinate2D] = []
        for i in 0..<sorted.count - 1 {
            let origin = CLLocationCoordinate2D(latitude: sorted[i].lat,   longitude: sorted[i].lng)
            let dest   = CLLocationCoordinate2D(latitude: sorted[i+1].lat, longitude: sorted[i+1].lng)
            if let result = try? await GoogleDirectionsService.route(from: origin, to: dest) {
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
            }
        }

        routeCoordinates = allCoords
        if !allCoords.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 60)
        } else if let first = sorted.first {
            cameraCommand = MapCameraCommand.focus(lat: first.lat, lng: first.lng, zoom: 11)
        }
    }
}

// MARK: - Participant Row

struct ParticipantRiderRow: View {
    let participant: RideParticipant
    var nameOverride: String? = nil
    var statusOverride: String? = nil
    var isOnline: Bool = false

    private var displayName: String { nameOverride ?? participant.name }
    private var displayStatus: String { statusOverride ?? participant.status }
    private var isReady: Bool { displayStatus == "READY" }

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                if let url = participant.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.surfaceVariant)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.surfaceVariant)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(displayName.prefix(1)).uppercased())
                                .font(.headlineMd).foregroundColor(Color.onSurface)
                        )
                }

                Circle()
                    .fill(isOnline ? Color.tertiaryFixed : Color.surfaceVariant)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName).font(.bodyLg).foregroundColor(Color.onSurface)
                    if participant.isLeader {
                        Text("LEADER")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onPrimaryFixed).tracking(1)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.primaryFixed).clipShape(Capsule())
                    }
                }
                Text(participant.isLeader ? "RIDE LEADER" : "FORMATION RIDER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.onSurfaceVariant).tracking(1)
            }

            Spacer()

            // Ready-state only — connection state is shown by the presence dot, never as a
            // "DISCONNECTED" badge (which conflated roster status with liveness).
            Text(isReady ? "READY" : "WAITING")
                .font(.labelCaps)
                .foregroundColor(isReady ? Color.onPrimaryContainer : Color.onSurfaceVariant)
                .tracking(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isReady ? Color.primaryContainer : Color.surfaceVariant)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isReady ? Color.primaryFixed : Color.outline, lineWidth: 1))
        .overlay(
            HStack {
                Rectangle()
                    .fill(isReady ? Color.primaryFixed : Color.outline)
                    .frame(width: 4).clipShape(RoundedRectangle(cornerRadius: 2))
                Spacer()
            }
        )
        .animation(.easeInOut(duration: 0.2), value: displayStatus)
    }
}

// MARK: - Remove Rider Sheet

struct RemoveRiderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let participant: RideParticipant
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(Color.outline).frame(width: 36, height: 4).padding(.top, 12)

            VStack(spacing: 12) {
                if let url = participant.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.surfaceVariant)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.surfaceVariant)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text(String(participant.name.prefix(1)).uppercased())
                                .font(.headlineLg).foregroundColor(Color.onSurface)
                        )
                }

                Text(participant.name).font(.headlineMd).foregroundColor(Color.onSurface)
                Text(participant.isLeader ? "RIDE LEADER" : "FORMATION RIDER")
                    .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
            }

            Button(action: onRemove) {
                HStack(spacing: 10) {
                    if isRemoving {
                        ProgressView().tint(Color.errorColor)
                    } else {
                        Image(systemName: "person.fill.xmark").font(.system(size: 18, weight: .bold))
                    }
                    Text(isRemoving ? "REMOVING..." : "REMOVE FROM RIDE")
                        .font(.headlineMd).tracking(-0.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.errorContainer)
                .foregroundColor(Color.errorColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isRemoving)

            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(.headlineMd).tracking(-0.5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundColor(Color.onSurfaceVariant)
                    .background(Color.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isRemoving)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceDim.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Supporting Views

struct ShareButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(Color.onSurface)
                .frame(width: 44, height: 44)
                .background(Color.surfaceContainerHigh.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.2), lineWidth: 1))
        }
    }
}

struct LobbyStartPin: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color.surfaceContainerHigh).frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2.5))
                    .shadow(color: Color.primaryFixed.opacity(0.4), radius: 8)
                Image(systemName: "mappin.circle.fill").font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.primaryFixed)
            }
            Triangle().fill(Color.primaryFixed).frame(width: 8, height: 5).offset(y: -1)
            Text("START").font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface).tracking(0.5)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.surfaceContainerHigh.opacity(0.92)).clipShape(Capsule())
        }
    }
}

struct QRCodeModal: View {
    @Environment(\.dismiss) private var dismiss
    var inviteCode: String = ""

    private var deepLinkURL: String {
        AppURLs.joinLink(code: inviteCode)
    }

    private var qrImage: UIImage? {
        guard !inviteCode.isEmpty,
              let data = deepLinkURL.data(using: .isoLatin1),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scale = UIScreen.main.scale * 10
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        ZStack {
            Color.surfaceDim.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 32) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark").font(.system(size: 20)).foregroundColor(Color.onSurfaceVariant)
                            .frame(width: 44, height: 44)
                    }
                }
                Text("JOIN CONVOTRACK").font(.headlineMd).foregroundColor(Color.primaryFixed).tracking(2)

                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.white).frame(width: 256, height: 256)
                    if let img = qrImage {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                    } else {
                        ProgressView().tint(Color.surfaceContainerLowest)
                    }
                }

                if !inviteCode.isEmpty {
                    VStack(spacing: 4) {
                        Text("INVITE CODE").font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                        Text(inviteCode).font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed).tracking(6)
                    }
                }
                Spacer()
            }
            .padding(24).padding(.top, 16)
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

import UIKit

struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, uiViewController.presentedViewController == nil else { return }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let sheet = activityVC.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        activityVC.completionWithItemsHandler = { _, _, _, _ in isPresented = false }
        uiViewController.present(activityVC, animated: true)
    }
}

#Preview {
    RideLobbyView()
        .environmentObject(AppState())
        .environment(Clerk.shared)
}
