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
    // Fired when the leader deletes the entire ride (received via ride:deleted).
    var onRideDeleted: (() -> Void)?

    // Leader can start when alone OR when all non-leaders have readied up
    /// Ride-wide readiness, for display only.
    ///
    /// Riders only: the leader has no MARK AS READY control (they get the Start button instead), so
    /// counting them would leave the tally permanently one short and looking stuck. This is the
    /// same population `canStart` already checks — but unlike `canStart` it is computed the same
    /// way on every device, which is the whole point: `canStart` returns false on its first line
    /// for non-leaders, so driving the STATUS pill from it made that pill read "Waiting" forever on
    /// every rider's phone, even after they had marked themselves ready.
    ///
    /// Nothing here gates anything. The Start button's rule and the server's start checks are
    /// untouched.
    var readyRiderTally: (ready: Int, total: Int) {
        let riders = participants.filter { !$0.isLeader }
        let ready = riders.filter { rider in
            // Own row uses the optimistic local state, matching how the roster renders it, so the
            // tally moves the instant you tap rather than waiting for the server echo.
            rider.userId == myUserId ? myStatus == "READY" : rider.status == "READY"
        }.count
        return (ready, riders.count)
    }

    var readyStatusText: String {
        let tally = readyRiderTally
        guard tally.total > 0 else { return "Solo" }
        return tally.ready == tally.total ? "All ready" : "\(tally.ready)/\(tally.total) ready"
    }

    var allRidersReady: Bool {
        let tally = readyRiderTally
        return tally.total == 0 || tally.ready == tally.total
    }

    var canStart: Bool {
        guard amILeader else { return false }
        let others = participants.filter { !$0.isLeader }
        return others.isEmpty || others.allSatisfy { $0.status == "READY" }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Mirror the shared `RideRealtimeSession` into this view model and translate its state into the
    /// view's callbacks. The session (owned by `MainTabView`) owns the socket, heartbeat,
    /// reconnect→rejoin and presence — the lobby only observes. Combine's multi-subscriber
    /// observation means this can't clobber the navigation screen's own subscription.
    func bind(to session: RideRealtimeSession) {
        cancellables.removeAll()

        session.$participants
            .sink { [weak self] participants in
                guard let self else { return }
                self.participants = participants
                // Clear the leader's in-flight removal spinner once the roster confirms the kick.
                if let removing = self.removingUserId,
                   !participants.contains(where: { $0.userId == removing }) {
                    self.removingUserId = nil
                }
            }
            .store(in: &cancellables)
        session.$onlineUserIds
            .sink { [weak self] in self?.onlineUserIds = $0 }
            .store(in: &cancellables)
        session.$leaderId
            .sink { [weak self] leaderId in if !leaderId.isEmpty { self?.leaderId = leaderId } }
            .store(in: &cancellables)
        session.$connectionState
            .sink { [weak self] in self?.socketConnected = ($0 == .connected) }
            .store(in: &cancellables)
        // Fire only on the LOBBY → ACTIVE transition so non-leader riders auto-advance to the
        // navigation screen when the leader starts the ride.
        session.$rideStatus
            .removeDuplicates()
            .sink { [weak self] status in if status == "ACTIVE" { self?.onRideStarted?() } }
            .store(in: &cancellables)
        session.$rideUpdated
            .compactMap { $0 }
            .sink { [weak self] event in self?.onRideUpdated?(event) }
            .store(in: &cancellables)
        session.$wasRemoved
            .filter { $0 }
            .sink { [weak self] _ in self?.onRemovedFromRide?() }
            .store(in: &cancellables)
        session.$wasDeleted
            .filter { $0 }
            .sink { [weak self] _ in self?.onRideDeleted?() }
            .store(in: &cancellables)
    }

    func markReady(rideId: String) {
        guard myStatus != "READY" else { return }
        // Optimistic update; the leader's roster reflects it via ride:participant_ready (which the
        // session applies). Own ready is overlaid locally at render via myStatus.
        myStatus = "READY"
        SocketClient.shared.emitReady(rideId: rideId) { [weak self] success in
            if !success { self?.myStatus = "WAITING" }   // rollback on ack failure
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
            removeError = error.riderMessage
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
                startError = error.riderMessage
            }
        } catch {
            startError = error.riderMessage
        }
        isStarting = false
    }
}

// MARK: - RideLobbyView

struct RideLobbyView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var rideSession: RideRealtimeSession
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
    @State private var wasDeleted = false
    @State private var showRideDeletedAlert = false
    // Chrome floating over the map preview, measured so the camera fit can frame the route
    // in the band that's actually visible. Defaults are first-frame fallbacks only — the
    // fit re-runs once the real values land.
    @State private var topChromeBottom: CGFloat = 100
    @State private var statPillsHeight: CGFloat = 76
    // Hero state for the destination photo. An explicit phase rather than an optional image:
    // "still resolving" and "there is no photo" must look different, otherwise switching rides
    // shows the map for a moment before the photo lands.
    @State private var heroPhase: DestinationHeroPhase = .resolving

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

    /// The leader may edit the ride in any state except COMPLETED (LOBBY, ACTIVE and PAUSED are
    /// all editable). Editing an ACTIVE ride re-routes everyone live (backend swaps the in-memory
    /// route geometry and broadcasts `ride:updated`; riders in navigation reroute with an alert).
    /// Leadership is read from both the reactive Clerk identity AND the VM's cached `amILeader` —
    /// the former survives app relaunch before the cache is seeded, the latter survives a transient
    /// render where `clerk.user` reads nil. Requires `currentRide` since `EditRideView` needs a
    /// ride to edit.
    private var canEditRide: Bool {
        guard let ride = appState.currentRide, ride.status != "COMPLETED" else { return false }
        if vm.amILeader { return true }
        if let uid = clerk.user?.id, !uid.isEmpty, uid == ride.leaderId { return true }
        return false
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack {
            HStack(spacing: 12) {
                Button(action: {
                    rideSession.stop()
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
            // Bottom edge of the top chrome in SCREEN coords. The map's top edge is screen
            // y=0 (the scroll view ignores the top safe area), so this single number is the
            // whole obscured region — notch/status bar included, with no assumption about
            // how SwiftUI propagated the safe area and no per-device constant.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxY.rounded(.up)
            } action: { bottom in
                topChromeBottom = bottom
            }
            if rideSession.connectionState == .reconnecting {
                ConnectionBanner(state: rideSession.connectionState)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: rideSession.connectionState)
            }
            Spacer()
        }
    }

    // MARK: - Body

    private var mainContent: some View {
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

            topOverlay

            bottomBar
        }
        // The chrome is measured after the first layout pass, so a route that loaded before
        // then was framed with the fallback insets. Re-fit when the real numbers arrive (and
        // on rotation, when they change again).
        .onChange(of: topChromeBottom) { _, _ in fitRouteToVisibleBand(routeCoordinates) }
        .onChange(of: statPillsHeight) { _, _ in fitRouteToVisibleBand(routeCoordinates) }
    }

    var body: some View {
        mainContent
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
        // Pushed, not presented as a sheet. Edit Ride is a long form that already carries page
        // chrome (inline title, back button, dark toolbar) — chrome that is inert inside a sheet,
        // since a sheet has no navigation container, which is why it appeared with no title, no
        // close button and no top margin. Its sibling CreateRideView is a pushed page for the same
        // reason, so the two now match.
        .navigationDestination(isPresented: $showEditSheet) {
            if let ride = appState.currentRide {
                EditRideView(ride: ride, onDeleted: { wasDeleted = true })
                    .environmentObject(appState)
                    .environmentObject(membershipStore)
            }
        }
        // A push has no `onDismiss`, so the pop is observed here instead.
        .onChange(of: showEditSheet) { wasShowing, isShowing in
            guard wasShowing, !isShowing else { return }
            if wasDeleted {
                // The leader deleted the ride from the edit page — tear down the session and exit
                // the lobby instead of refreshing a ride that no longer exists.
                rideSession.stop()
                appState.currentRideId = nil   // also clears currentRide
                appState.inviteCode = nil
                dismiss()
            } else {
                Task { await refreshAfterEdit() }
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
        .modifier(lobbyAlerts)
        .task { await loadRideAndConnect() }
        // Keyed on the destination so it runs once the ride lands (the lobby renders before
        // the fetch returns) and again if the leader edits the destination.
        .task(id: destinationPhotoKey) { await loadDestinationPhoto() }
        .preferredColorScheme(.dark)
    }

    /// The lobby's alerts + their triggers, bundled so the `body` modifier chain stays
    /// short enough for the Swift type-checker.
    private var lobbyAlerts: some ViewModifier {
        LobbyAlerts(
            showStartError: $showStartError,
            showRemoveError: $showRemoveError,
            showRemovedAlert: $showRemovedAlert,
            showRideDeletedAlert: $showRideDeletedAlert,
            startError: vm.startError,
            removeError: vm.removeError,
            onExit: {
                appState.currentRideId = nil   // also clears currentRide
                appState.inviteCode = nil
                dismiss()
            }
        )
    }

    // MARK: - Map Section

    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            // Three outcomes, three appearances: blank while we don't yet know, the photo when
            // Google has one, the route map when it doesn't. Collapsing "resolving" into the map
            // case is what caused the ride-switch glitch — the map appeared for a beat and was
            // then replaced by the photo.
            switch heroPhase {
            case .resolving:
                // Deliberately empty: neither the photo nor the map. Showing the map here is
                // what made a ride switch flash map → photo. A plain surface reads as "loading"
                // without committing to either outcome.
                Color.surfaceContainerLow
                    .frame(maxWidth: .infinity)
                    .frame(height: mapPreviewHeight)

            case .photo(let photo):
                // A fixed-size container owns the layout and the photo is decoration INSIDE it,
                // via `.overlay`. Sizing the Image itself leaks its aspect ratio outward: a 16:9
                // photo filling 420pt of height reports a 747pt-wide view, which widened this
                // whole page to 747pt and shifted every element — title, pills, roster — 177pt
                // left of the screen. `.clipped()` cannot save it; clipping trims pixels after
                // layout is already decided. An overlay never resizes its parent, so the photo
                // and the chrome are now on genuinely independent layout planes.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: mapPreviewHeight)
                    .overlay {
                        // Arbitrary photo into a near-square slot: show the WHOLE photo
                        // (`scaledToFit`, nothing cropped) over a blurred, zoomed copy of itself
                        // that fills the leftover space. A plain `scaledToFill` crop would show
                        // only 53% of a 16:9 photo's width, and `scaledToFit` alone would leave
                        // ~200pt of dead bands. This handles any aspect — landscape or portrait —
                        // without the slot's height having to change.
                        ZStack {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 24, opaque: true)
                                .overlay(Color.black.opacity(0.25))
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .clipped()
                    .transition(.opacity)

            case .unavailable:
                GoogleMapView(
                    routeCoords:   routeCoordinates,
                    stopCoords:    lobbyStopCoords,
                    pins:          lobbyMapPins,
                    cameraCommand: cameraCommand,
                    isInteractive: false
                )
                .frame(maxWidth: .infinity, minHeight: mapPreviewHeight)
                .transition(.opacity)
            }

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
            .frame(height: mapPreviewHeight)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FloatingStatPill(label: "DISTANCE", value: distanceKm, unit: "km")
                    FloatingStatPill(label: "RIDERS", value: "\(vm.participants.count)", unit: nil)
                    FloatingStatPill(
                        label: "STATUS",
                        value: vm.readyStatusText,
                        unit: nil,
                        dotColor: vm.allRidersReady ? Color.primaryFixed : Color.secondaryFixed
                    )
                    if !inviteCode.isEmpty {
                        FloatingStatPill(label: "CODE", value: inviteCode, unit: nil)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            // Pills keep floating over the map; the camera fit is what moves. Measuring the
            // row (bottom padding included) means the route is framed above it whatever the
            // pill content does — an extra CODE pill, a longer value, a bigger text size.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded(.up)
            } action: { height in
                statPillsHeight = height
            }

            photoAttribution
        }
        .frame(height: mapPreviewHeight)
        .animation(.easeInOut(duration: 0.35), value: heroPhase)
    }

    /// Height of the map preview. Shared by the frame, the fade gradient and the camera-fit
    /// clamp so they can't drift apart.
    private var mapPreviewHeight: CGFloat { 420 }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        guard let ride = appState.currentRide else { return nil }
        return CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng)
    }

    /// Identity of the destination we want a photo for; empty until this lobby's own ride has
    /// loaded. The `id` check is what stops a ride switch from showing the previous ride's photo:
    /// `currentRideId` changes immediately, but `currentRide` still holds the OLD ride until its
    /// fetch returns, and that stale destination would otherwise hit the cache and render.
    private var destinationPhotoKey: String {
        guard let ride = appState.currentRide,
              ride.id == appState.currentRideId,
              !ride.destinationName.isEmpty
        else { return "" }
        return "\(ride.id)|\(ride.destinationName)|\(ride.destinationLat),\(ride.destinationLng)"
    }

    private func loadDestinationPhoto() async {
        let key = destinationPhotoKey
        // No ride yet (or it isn't ours yet): stay blank rather than showing the map, which
        // would only be replaced a moment later.
        guard !key.isEmpty, let coordinate = destinationCoordinate else {
            heroPhase = .resolving
            return
        }

        // Anything held for a different destination is stale the instant the key changes.
        heroPhase = .resolving

        let fetched = await GooglePlacePhotoService.shared.photo(
            destinationName: destinationName,
            coordinate: coordinate
        )
        // A newer `.task(id:)` may have superseded this one (ride switched, destination edited).
        guard !Task.isCancelled, key == destinationPhotoKey else { return }
        heroPhase = fetched.map { .photo($0) } ?? .unavailable
    }

    /// Photographer credit for the destination photo. Required by Google's Places policy
    /// whenever a Place Photo is displayed, so it renders with the image rather than being
    /// optional decoration. Sits just above the stat pills, using their measured height.
    @ViewBuilder
    private var photoAttribution: some View {
        if case .photo(let photo) = heroPhase, let attribution = photo.attribution {
            Text("Photo: \(attribution) · Google")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.7), radius: 3)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.bottom, statPillsHeight + 2)
        }
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
                        let row = ParticipantRiderRow(participant: participant, nameOverride: name, statusOverride: status, isOnline: vm.onlineUserIds.contains(participant.userId), rideActive: appState.currentRide?.status == "ACTIVE")
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
                        appState.currentRide = ride.with(status: "ACTIVE")
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

        var seedParticipants: [RideParticipant] = []
        var seedLeaderId = ""
        if let ride = appState.currentRide {
            vm.myUserId = clerk.user?.id ?? ""
            vm.leaderId = ride.leaderId
            vm.participants = ride.participants
            seedParticipants = ride.participants
            seedLeaderId = ride.leaderId
            // Sync own initial status from server
            if let me = ride.participants.first(where: { $0.userId == vm.myUserId }) {
                vm.myStatus = me.status
            }
        }

        if let ride = appState.currentRide {
            await calculateRoute(from: ride.waypoints, polyline: ride.routePolyline)
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
                routePolyline: event.routePolyline,
                startedAt: existing.startedAt,
                endedAt: existing.endedAt,
                createdAt: existing.createdAt,
                waypoints: event.waypoints,
                participants: existing.participants
            )
            Task { await calculateRoute(from: event.waypoints, polyline: event.routePolyline) }
        }

        // Ride is/became ACTIVE: reflect the status locally so the bottom bar shows
        // RESUME NAVIGATION. Do NOT auto-navigate — the rider stays on the lobby and taps
        // RESUME to enter navigation. (The leader's own Start button navigates directly.)
        vm.onRideStarted = { [appState] in
            if let ride = appState.currentRide, ride.status != "ACTIVE" {
                appState.currentRide = ride.with(status: "ACTIVE")
            }
        }

        // I was removed by the leader — tear down the shared session and surface an alert.
        vm.onRemovedFromRide = { [rideSession] in
            rideSession.stop()
            showRemovedAlert = true
        }

        // The leader deleted the whole ride. Non-leaders learn of it only via this
        // broadcast and get an alert; the leader initiated it locally and exits through
        // the edit-sheet dismissal, so it needs no second prompt for them.
        vm.onRideDeleted = { [weak vm, rideSession] in
            rideSession.stop()
            if vm?.amILeader != true {
                showRideDeletedAlert = true
            }
        }

        // Start the shared realtime session (idempotent), then mirror its state into the VM.
        if let token = try? await Clerk.shared.auth.getToken() {
            rideSession.start(rideId: rideId, token: token, myUserId: vm.myUserId,
                              seedParticipants: seedParticipants, leaderId: seedLeaderId)
        }
        vm.bind(to: rideSession)
    }

    @MainActor
    private func refreshAfterEdit() async {
        guard let rideId = appState.currentRideId else { return }
        if let ride = try? await APIClient.shared.getRide(rideId) {
            appState.currentRide = ride
            await calculateRoute(from: ride.waypoints, polyline: ride.routePolyline)
        }
    }

    /// Frames the route inside the map's *visible* band rather than its full 420pt frame.
    /// A uniform padding can't work here: the top is covered by the notch and the back/title
    /// row, the bottom by the floating stat pills, and the stop pins tower 84pt above their
    /// own coordinates — so a symmetric fit put the start and destination markers underneath
    /// that chrome. Effectively this zooms the preview out just enough to clear it.
    @MainActor
    private func fitRouteToVisibleBand(_ coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        let rawTop    = topChromeBottom + GoogleMapView.stopPinTopExtent + 8
        let rawBottom = statPillsHeight + 8
        // The insets must leave a usable band — asking GMS to fit into a zero-height
        // viewport yields a nonsense zoom. Scale both back proportionally if the chrome ever
        // grows enough to threaten that (larger text, more pills), keeping their ratio so
        // the route stays centred in whatever band is left.
        let maxVertical = mapPreviewHeight - 80
        let squeeze = min(1, maxVertical / max(rawTop + rawBottom, 1))
        cameraCommand = MapCameraCommand.fitRouteInsets(
            coords,
            top:    rawTop * squeeze,
            left:   56,
            bottom: rawBottom * squeeze,
            right:  56,
            animated: true
        )
    }

    @MainActor
    private func calculateRoute(from waypoints: [Waypoint], polyline: String? = nil) async {
        // Prefer the leader-selected route geometry stored on the ride.
        if let stored = GoogleDirectionsService.decodedRoute(polyline) {
            routeCoordinates = stored
            fitRouteToVisibleBand(stored)
            return
        }

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
            fitRouteToVisibleBand(allCoords)
        } else if let first = sorted.first {
            cameraCommand = MapCameraCommand.focus(lat: first.lat, lng: first.lng, zoom: 11)
        }
    }
}

// MARK: - Lobby Alerts

/// Bundles the lobby's four alerts and their `onChange` triggers. Extracted from
/// `RideLobbyView.body` purely to keep that view's modifier chain within the Swift
/// type-checker's complexity budget.
private struct LobbyAlerts: ViewModifier {
    @Binding var showStartError: Bool
    @Binding var showRemoveError: Bool
    @Binding var showRemovedAlert: Bool
    @Binding var showRideDeletedAlert: Bool
    let startError: String?
    let removeError: String?
    let onExit: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Couldn't Start Ride", isPresented: $showStartError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(startError ?? "An error occurred.")
            }
            .onChange(of: startError) { _, err in
                if err != nil { showStartError = true }
            }
            .alert("Couldn't Remove Rider", isPresented: $showRemoveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(removeError ?? "An error occurred.")
            }
            .onChange(of: removeError) { _, err in
                if err != nil { showRemoveError = true }
            }
            .alert("Removed From Ride", isPresented: $showRemovedAlert) {
                Button("OK", role: .cancel) { onExit() }
            } message: {
                Text("The ride leader removed you from this ride.")
            }
            .alert("Ride Cancelled", isPresented: $showRideDeletedAlert) {
                Button("OK", role: .cancel) { onExit() }
            } message: {
                Text("The ride leader cancelled this ride.")
            }
    }
}

// MARK: - Participant Row

struct ParticipantRiderRow: View {
    let participant: RideParticipant
    var nameOverride: String? = nil
    var statusOverride: String? = nil
    var isOnline: Bool = false
    /// True once the ride has left the lobby (status ACTIVE). Everyone is riding, so the
    /// ready/waiting distinction is moot and the badge reads "RIDING".
    var rideActive: Bool = false

    private enum RosterState: Equatable { case waiting, ready, riding }

    private var displayName: String { nameOverride ?? participant.name }
    private var displayStatus: String { statusOverride ?? participant.status }

    // The leader starts the ride rather than readying up, so a leader must never render as
    // WAITING. Once the ride is ACTIVE everyone is riding.
    private var rosterState: RosterState {
        if rideActive { return .riding }
        if participant.isLeader || displayStatus == "READY" { return .ready }
        return .waiting
    }
    private var isActive: Bool { rosterState != .waiting }

    private var badgeText: String {
        switch rosterState {
        case .waiting: return "WAITING"
        case .ready:   return "READY"
        case .riding:  return "RIDING"
        }
    }
    private var badgeTextColor: Color {
        switch rosterState {
        case .waiting: return Color.onSurfaceVariant
        case .ready:   return Color.onPrimaryContainer
        case .riding:  return Color.onPrimaryFixed
        }
    }
    private var badgeBackground: Color {
        switch rosterState {
        case .waiting: return Color.surfaceVariant
        case .ready:   return Color.primaryContainer
        case .riding:  return Color.tertiaryFixed
        }
    }
    private var accentColor: Color {
        switch rosterState {
        case .waiting: return Color.outline
        case .ready:   return Color.primaryFixed
        case .riding:  return Color.tertiaryFixed
        }
    }

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

            // Roster state (waiting / ready / riding) — connection state is shown by the presence
            // dot, never as a "DISCONNECTED" badge (which conflated roster status with liveness).
            Text(badgeText)
                .font(.labelCaps)
                .foregroundColor(badgeTextColor)
                .tracking(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(badgeBackground)
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.surfaceContainerHigh.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isActive ? accentColor : Color.outline, lineWidth: 1))
        .overlay(
            HStack {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 4).clipShape(RoundedRectangle(cornerRadius: 2))
                Spacer()
            }
        )
        .animation(.easeInOut(duration: 0.2), value: rosterState)
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
