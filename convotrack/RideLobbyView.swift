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
    @Published var isLeaving = false
    @Published var leaveError: String? = nil

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

    /// Leave the ride I'm in. Returns true once the server has confirmed.
    ///
    /// Confirmation-first, deliberately: the caller tears down the shared realtime session on
    /// success, and doing that optimistically would drop the socket before the server's
    /// `ride:participant_left` broadcast — the very event every other rider's roster, ready
    /// tally, leaderboard and map pin removal hangs off.
    ///
    /// "You aren't in this ride" counts as success. The rider asked to be out; if the server
    /// already has them out (double tap, a stale lobby, a leader who kicked them a moment
    /// earlier), the goal is met and trapping them behind an error alert would be absurd.
    func leaveRide() async -> Bool {
        guard !isLeaving else { return false }
        isLeaving = true
        leaveError = nil
        defer { isLeaving = false }
        do {
            try await APIClient.shared.leaveRide(rideId)
            await ImageCache.shared.purge(tag: rideId)
            return true
        } catch APIClientError.serverError(let code)
                    where code == "PARTICIPANT_NOT_FOUND" || APIClient.isNotFound(code) {
            return true
        } catch {
            leaveError = error.riderMessage
            return false
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
    @EnvironmentObject private var paywall: PaywallPresenter
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
    @State private var showLeaveConfirm = false
    @State private var showLeaveError = false
    @State private var wasDeleted = false
    @State private var showRideDeletedAlert = false
    // Chrome floating over the map preview, measured so the camera fit can frame the route
    // in the band that's actually visible. Defaults are first-frame fallbacks only — the
    // fit re-runs once the real values land.
    @State private var topChromeBottom: CGFloat = 100
    /// Status bar + nav bar height, so the hero (which runs under them) keeps a fixed visible band.
    @State private var heroTopInset: CGFloat = 106
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

    // MARK: - Toolbar

    /// System back/edit/more buttons. On iOS 26 toolbar items float over the hero as Liquid Glass
    /// circles; `ToolbarSpacer` keeps edit and more as separate capsules.
    @ToolbarContentBuilder
    private var lobbyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                rideSession.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.backward").foregroundStyle(DS.Text.primary)
            }
            .accessibilityLabel(Text("Back"))
        }
        if canEditRide {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditSheet = true } label: { Image(systemName: "pencil").foregroundStyle(DS.Text.primary) }
                    .accessibilityLabel(Text("Edit ride"))
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }

    /// Share, QR and (riders only) Leave live in one menu instead of a row of circles.
    private var moreMenu: some View {
        Menu {
            Button { showShareSheet = true } label: {
                Label("Share Invite", systemImage: "square.and.arrow.up")
            }
            Button { showQRModal = true } label: {
                Label("Show QR Code", systemImage: "qrcode")
            }
            if canLeaveRide {
                Button(role: .destructive) { showLeaveConfirm = true } label: {
                    Label("Leave Ride", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(vm.isLeaving)
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(DS.Text.primary)
        }
        .accessibilityLabel(Text("More"))
    }

    // MARK: - Body

    private func lobbyContent(topInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            DSScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    lobbyHero
                    VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                        detailsSection
                        rosterSection
                    }
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.top, DS.Space.p5)
                    .padding(.bottom, DS.Space.sectionGap)
                }
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .top)

            if rideSession.connectionState == .reconnecting {
                DSReconnectingBanner()
                    .padding(.horizontal, DS.Space.screenInset)
                    .padding(.top, topInset + 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .dsAnimation(DS.Motion.emphasized, value: rideSession.connectionState)
        // The chrome is measured after the first layout pass, so a route that loaded before
        // then was framed with the fallback insets. Re-fit when the real numbers arrive (and
        // on rotation, when they change again).
        .onChange(of: topInset, initial: true) { _, inset in
            heroTopInset = inset
            topChromeBottom = inset
        }
        .onChange(of: topChromeBottom) { _, _ in fitRouteToVisibleBand(routeCoordinates) }
        .onChange(of: statPillsHeight) { _, _ in fitRouteToVisibleBand(routeCoordinates) }
    }

    var body: some View {
        GeometryReader { proxy in
            lobbyContent(topInset: proxy.safeAreaInsets.top)
        }
        // Sticky action sits above the tab bar, which stays visible with Home selected.
        .dsStickyBottomAction { bottomAction }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        .toolbar { lobbyToolbar }
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
        .alert("Leave This Ride?", isPresented: $showLeaveConfirm) {
            Button("Leave Ride", role: .destructive) { Task { await leaveRide() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stop sharing your location and drop off the roster. You can re-join later with the invite code.")
        }
        .modifier(lobbyAlerts)
        .task { await loadRideAndConnect() }
        // Live Activity tap: push navigation as soon as the ride is loaded and ACTIVE.
        .onAppear(perform: openNavigationIfRequested)
        .onChange(of: appState.openNavigationRideId) { _, _ in openNavigationIfRequested() }
        .onChange(of: appState.currentRide?.status) { _, _ in openNavigationIfRequested() }
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
            showLeaveError: $showLeaveError,
            startError: vm.startError,
            removeError: vm.removeError,
            leaveError: vm.leaveError,
            onExit: {
                appState.currentRideId = nil   // also clears currentRide
                appState.inviteCode = nil
                dismiss()
            }
        )
    }

    // MARK: - Hero

    /// Title, live line and destination over the photo (or route map), with the Places credit
    /// pill at the bottom-end. The media is the background, so the hero grows with the text at
    /// large Dynamic Type sizes instead of clipping it.
    private var lobbyHero: some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            heroTitleBlock
            photoAttribution
        }
        // Measured so the route camera is framed above the title, not underneath it.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height.rounded(.up)
        } action: { height in
            statPillsHeight = height
        }
        .padding(.horizontal, DS.Space.screenInset)
        .padding(.top, heroTopInset + 24)
        .padding(.bottom, DS.Space.p4)
        .frame(maxWidth: .infinity, minHeight: mapPreviewHeight, alignment: .bottomLeading)
        .background { heroMedia }
        .dsAnimation(.easeInOut(duration: 0.35), value: heroPhase)
    }

    private var statusLine: LocalizedStringKey {
        appState.currentRide?.status == "ACTIVE" ? "Riding" : "In lobby"
    }

    private var heroTitleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.p2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ride").dsText(.eyebrow).foregroundStyle(DS.Text.label)
                Text(rideTitle)
                    .dsText(.heroTitle)
                    .foregroundStyle(DS.Text.onPhoto)
                    .lineLimit(2)
                    .dsShadow(DS.Shadow.textOnPhoto)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: DS.Space.p2) {
                Circle().fill(DS.Accent.base).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(statusLine).dsText(.bodyStrong).foregroundStyle(DS.Accent.base)
            }
            if !destinationName.isEmpty {
                Label {
                    Text(destinationName).dsText(.body).lineLimit(2)
                } icon: {
                    Image(systemName: "mappin").dsIcon(DS.IconSize.md)
                }
                .foregroundStyle(DS.Text.secondary)
                .dsShadow(DS.Shadow.textOnPhoto)
            }
        }
    }

    /// Three outcomes, three appearances: blank while we don't yet know, the photo when Google has
    /// one, the route map when it doesn't. Collapsing "resolving" into the map case is what caused
    /// the ride-switch glitch — the map appeared for a beat and was then replaced by the photo.
    private var heroMedia: some View {
        ZStack {
            switch heroPhase {
            case .resolving:
                // Deliberately empty: neither the photo nor the map.
                DS.Surface.raised

            case .photo(let photo):
                // The photo is decoration inside a fixed layout plane (`.overlay` never resizes
                // its parent); sizing the Image directly leaked its aspect ratio outward once and
                // widened the whole page.
                Color.clear
                    .overlay {
                        // Whole photo (`scaledToFit`) over a blurred, zoomed copy of itself that
                        // fills the leftover space, so any aspect works without cropping.
                        ZStack {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 24, opaque: true)
                                .overlay(Color.black.opacity(0.35))
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
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Keeps the toolbar buttons legible over a bright photo, then fades into the base.
            LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .top)
            DS.Gradient.photoFade
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)   // decorative; an overflowing photo must not swallow taps
    }

    // MARK: - Ride details

    @State private var codeCopied = false

    private var detailRows: [DSDetailRow] {
        let ride = appState.currentRide
        let start = ride?.waypoints.first(where: { $0.type == "START" })?.name
        var rows: [DSDetailRow] = [
            DSDetailRow(systemImage: "location.north.fill", label: "Start point", value: start ?? "--"),
            DSDetailRow(systemImage: "flag.fill", label: "Destination", value: destinationName.isEmpty ? "--" : destinationName, tag: "destination"),
            DSDetailRow(systemImage: "point.topleft.down.to.point.bottomright.curvepath", label: "Distance",
                        value: (ride?.distanceMeters ?? 0) > 0 ? String(format: "%.1f km", (ride?.distanceMeters ?? 0) / 1000) : "--"),
            DSDetailRow(systemImage: "clock", label: "Estimated time", value: RideDuration.inline(ride?.estimatedDurationSeconds)),
        ]
        if !inviteCode.isEmpty {
            rows.append(DSDetailRow(systemImage: "key", label: "Joining code", value: inviteCode, isMono: true, tag: "code"))
        }
        return rows
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Ride details")
            DSDetailsList(rows: detailRows) { row in
                switch row.tag {
                case "destination":
                    if let coordinate = destinationCoordinate {
                        DSSquareIconButton(systemImage: "location.north.fill", label: "Open in Maps") {
                            openInMaps(coordinate)
                        }
                    }
                case "code":
                    DSSquareIconButton(systemImage: codeCopied ? "checkmark" : "doc.on.doc", label: "Copy code") {
                        UIPasteboard.general.string = inviteCode
                        codeCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            codeCopied = false
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let name = destinationName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(name)") {
            UIApplication.shared.open(url)
        }
    }

    /// Height of the hero. Shared by the frame and the camera-fit clamp so they can't drift apart.
    /// The hero runs under the status bar and nav bar, so their height is added to the visible band.
    private var mapPreviewHeight: CGFloat { heroTopInset + 250 }

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

    /// Photographer credit for the destination photo. Required by Google's Places policy whenever
    /// a Place Photo is displayed, so it renders with the image rather than being optional
    /// decoration: a glass pill at the photo's bottom-end.
    @ViewBuilder
    private var photoAttribution: some View {
        if case .photo(let photo) = heroPhase, let attribution = photo.attribution {
            HStack {
                Spacer(minLength: 0)
                Text("Photo: \(attribution) · Google")
                    .dsText(.micro)
                    .foregroundStyle(DS.Text.onPhotoMuted)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.p3)
                    .frame(minHeight: 28)
                    .dsGlass(clear: true)
            }
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

    /// Leader first, then everyone else in server order.
    private var orderedParticipants: [RideParticipant] {
        vm.participants.filter { $0.isLeader } + vm.participants.filter { !$0.isLeader }
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading(title: "Squad roster") {
                HStack(spacing: 8) {
                    DSSquareIconButton(systemImage: "link", label: "Share invite") { showShareSheet = true }
                    DSSquareIconButton(systemImage: "qrcode", label: "Show QR code") { showQRModal = true }
                }
            }
            // Live state and the ready tally sit under the heading; with the two buttons they
            // don't all fit on the heading's line at 402 pt.
            HStack(spacing: DS.Space.p3) {
                if vm.socketConnected { DSLiveIndicator() }
                Text(LocalizedStringKey(vm.readyStatusText))
                    .dsText(.badge)
                    .foregroundStyle(vm.allRidersReady ? DS.Accent.base : DS.Text.muted.base)
                Spacer(minLength: 0)
                riderCapChip
            }
            .padding(.bottom, DS.Space.p3)

            if vm.participants.isEmpty {
                DSLoadingState()
            } else {
                VStack(spacing: DS.Space.listGap) {
                    ForEach(orderedParticipants, id: \.userId) { participant in
                        rosterRow(participant)
                    }
                }
            }
        }
    }

    /// Free leader only: how full the ride is against the plan's cap. Within one seat of the cap it
    /// turns into the way to a bigger pack.
    @ViewBuilder private var riderCapChip: some View {
        if canEditRide, !membershipStore.isPremium,
           let cap = appState.currentRide?.maxAllowedParticipants, !vm.participants.isEmpty {
            let count = vm.participants.count
            let nearCap = count >= cap - 1
            Button {
                paywall.present(.riderCap)
            } label: {
                HStack(spacing: 5) {
                    if nearCap { Image(systemName: "lock.fill").dsIcon(11, weight: .semibold) }
                    Text("\(count)/\(cap) riders")
                }
                .dsText(.badge)
                .foregroundStyle(nearCap ? DS.Accent.base : DS.Text.muted.base)
                .frame(minHeight: DS.Target.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!nearCap)
            .accessibilityLabel(Text("\(count) of \(cap) riders"))
            .accessibilityHint(nearCap ? Text("Shows ConvoTrack Pro plans for bigger packs") : Text(""))
        }
    }

    @ViewBuilder
    private func rosterRow(_ participant: RideParticipant) -> some View {
        let isMe = participant.userId == vm.myUserId
        let name = isMe ? (myClerkName ?? participant.name) : participant.name
        let status = isMe ? vm.myStatus : participant.status
        // The leader can tap any non-leader rider to open the management sheet (remove from ride).
        let canManage = vm.amILeader && participant.userId != vm.leaderId
        // The leader starts the ride rather than readying up, so a leader never reads as
        // WAITING. Once the ride is ACTIVE everyone is riding.
        let badge: DSStatusBadge.Kind = appState.currentRide?.status == "ACTIVE" ? .riding
            : (participant.isLeader || status == "READY") ? .ready : .waiting
        let row = DSRosterRow(
            name: name,
            id: participant.userId,
            imageURL: participant.avatarUrl.flatMap(URL.init(string:)),
            isMe: isMe,
            isLeader: participant.isLeader,
            isOnline: vm.onlineUserIds.contains(participant.userId),
            badge: badge,
            showsChevron: canManage
        )
        if canManage {
            Button { participantToManage = participant } label: { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func openNavigationIfRequested() {
        guard let id = appState.openNavigationRideId, id == vm.rideId || id == appState.currentRideId else { return }
        guard let status = appState.currentRide?.status else { return }   // not loaded yet; retried on change
        appState.openNavigationRideId = nil
        if status == "ACTIVE" { showNavigation = true }
    }

    // MARK: - Sticky action

    @ViewBuilder
    private var bottomAction: some View {
        if appState.currentRide?.status == "ACTIVE" {
            DSPrimaryButton(title: "Resume navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                showNavigation = true
            }
        } else if vm.amILeader {
            DSPrimaryButton(
                title: vm.canStart ? "Start ride" : "Waiting for riders",
                systemImage: vm.canStart ? "play.fill" : "clock",
                isLoading: vm.isStarting
            ) {
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
            }
            .disabled(!vm.canStart || vm.isStarting)
        } else if vm.myStatus == "READY" {
            DSSecondaryButton(title: "You're ready", isConfirmed: true) {}
                .disabled(true)
        } else {
            // Marking ready is the rider's one next action, so it carries the lime.
            DSPrimaryButton(title: "Mark as ready", systemImage: "checkmark.circle") {
                vm.markReady(rideId: vm.rideId)
            }
        }
    }

    /// Whether to offer LEAVE RIDE. Riders only, in both LOBBY and ACTIVE — a rider who has to
    /// peel off mid-ride is exactly who needs this, and waiting for the leader to kick them is
    /// not an answer.
    ///
    /// The leader has no equivalent: leaving would orphan the ride, leaving nobody able to start,
    /// end or edit it, so they cancel it from the edit page instead (the server rejects a leader
    /// leave with `LEADER_CANNOT_LEAVE` regardless of what the UI does).
    ///
    /// Leadership is read from both the VM's cached `amILeader` AND the reactive Clerk identity,
    /// the same belt-and-braces `canEditRide` uses — inverted here, because the cost of guessing
    /// wrong is reversed: a missing Edit button is a nuisance, a LEAVE button flashed at the
    /// leader during the load window is an invitation to break their own ride.
    private var canLeaveRide: Bool {
        guard let ride = appState.currentRide, ride.status != "COMPLETED" else { return false }
        if vm.amILeader { return false }
        if let uid = clerk.user?.id, !uid.isEmpty, uid == ride.leaderId { return false }
        return true
    }

    /// Exits the ride on this device once the server has confirmed the leave. Same teardown the
    /// "removed by the leader" path uses: stop the shared session, drop the persisted active
    /// ride, pop back to Home. On failure the alert fires and the rider stays put.
    @MainActor
    private func leaveRide() async {
        guard await vm.leaveRide() else { return }
        rideSession.stop()
        appState.currentRideId = nil   // also clears currentRide
        appState.inviteCode = nil
        dismiss()
    }

    // MARK: - Load + Connect

    private func loadRideAndConnect() async {
        guard let rideId = appState.currentRideId else { return }
        vm.rideId = rideId
        // Set unconditionally, not inside the `if let ride` below. `amILeader` — and therefore
        // whether the leader gets START RIDE or a rider's MARK AS READY button — is derived from
        // this, so burying it behind a successful fetch meant one failed request silently demoted
        // the leader on their own ride.
        vm.myUserId = clerk.user?.id ?? ""

        // Always fetch fresh — ride status may have changed since last visit (e.g. LOBBY → ACTIVE).
        // Retried, because this screen fetches exactly once: a single failure left it with no hero
        // photo, no route, no distance and no leader controls, and nothing on screen to try again.
        if let ride = await APIClient.shared.getRideRetrying(rideId) {
            appState.currentRide = ride
        }

        var seedParticipants: [RideParticipant] = []
        var seedLeaderId = ""
        if let ride = appState.currentRide {
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

/// Bundles the lobby's alerts and their `onChange` triggers. Extracted from
/// `RideLobbyView.body` purely to keep that view's modifier chain within the Swift
/// type-checker's complexity budget.
private struct LobbyAlerts: ViewModifier {
    @Binding var showStartError: Bool
    @Binding var showRemoveError: Bool
    @Binding var showRemovedAlert: Bool
    @Binding var showRideDeletedAlert: Bool
    @Binding var showLeaveError: Bool
    let startError: String?
    let removeError: String?
    let leaveError: String?
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
            .alert("Couldn't Leave Ride", isPresented: $showLeaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(leaveError ?? "An error occurred.")
            }
            .onChange(of: leaveError) { _, err in
                if err != nil { showLeaveError = true }
            }
            .alert("Ride Cancelled", isPresented: $showRideDeletedAlert) {
                Button("OK", role: .cancel) { onExit() }
            } message: {
                Text("The ride leader cancelled this ride.")
            }
    }
}

// MARK: - Remove Rider Sheet

struct RemoveRiderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let participant: RideParticipant
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.p6) {
            VStack(spacing: DS.Space.p3) {
                DSAvatar(
                    name: participant.name,
                    id: participant.userId,
                    imageURL: participant.avatarUrl.flatMap(URL.init(string:)),
                    size: DS.AvatarSize.xl
                )
                Text(participant.name).dsText(.titleLarge).foregroundStyle(DS.Text.primary)
                Text(participant.isLeader ? "Ride leader" : "Formation rider")
                    .dsText(.badge)
                    .foregroundStyle(DS.Text.muted)
            }
            VStack(spacing: DS.Space.p3) {
                // The destructive action is never the primary role.
                DSDestructiveButton(
                    title: "Remove from ride",
                    systemImage: "person.fill.xmark",
                    isLoading: isRemoving,
                    action: onRemove
                )
                DSSecondaryButton(title: "Cancel") { dismiss() }
                    .disabled(isRemoving)
            }
        }
        .padding(.horizontal, DS.Space.screenInset)
        .padding(.top, DS.Space.p8)
        .padding(.bottom, DS.Space.p5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Surface.sheet)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Supporting Views

struct LobbyStartPin: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(DS.Surface.raised).frame(width: 36, height: 36)
                    .overlay(Circle().stroke(DS.Accent.base, lineWidth: 2.5))
                Image(systemName: "mappin.circle.fill").font(.system(size: 20, weight: .bold))
                    .foregroundColor(DS.Accent.base)
            }
            Triangle().fill(DS.Accent.base).frame(width: 8, height: 5).offset(y: -1)
            Text("START").font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(DS.Text.primary.base).tracking(0.5)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(DS.Surface.raised.opacity(0.92)).clipShape(Capsule())
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
        ScrollView {
            VStack(spacing: DS.Space.p6) {
                HStack {
                    Spacer()
                    DSSquareIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                Text("Join ConvoTrack")
                    .dsText(.headerTitle)
                    .foregroundStyle(DS.Text.primary)
                    .accessibilityAddTraits(.isHeader)

                // The code stays black on white whatever the theme, so scanners can read it.
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(Color.white)
                    if let img = qrImage {
                        Image(uiImage: img)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                            .accessibilityLabel(Text("QR code for invite \(inviteCode)"))
                    } else {
                        ProgressView().tint(DS.Background.deep)
                    }
                }
                .frame(width: 240, height: 240)

                if !inviteCode.isEmpty {
                    VStack(spacing: DS.Space.p1) {
                        Text("Invite code").dsText(.fieldLabel).foregroundStyle(DS.Text.muted)
                        Text(inviteCode).dsText(.codeDisplay).foregroundStyle(DS.Accent.base)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, DS.Space.p6)
            .padding(.vertical, DS.Space.p4)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Surface.sheet)
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
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
        .environment(Clerk.shared)
}
