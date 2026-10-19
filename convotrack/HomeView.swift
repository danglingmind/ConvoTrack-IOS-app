import SwiftUI
import CoreLocation
import ClerkKit

enum HomeRoute: Hashable {
    case createRide
    case rideLobby
}

enum NearbyLoadState {
    case loading, loaded, locationDenied, error
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var rideSession: RideRealtimeSession
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var membershipStore: MembershipStore
    @EnvironmentObject private var paywall: PaywallPresenter
    @Binding var activeTab: AppTab
    @Binding var showJoinRide: Bool
    @State private var navPath = NavigationPath()
    @State private var nearbyRides: [NearbyRide] = []
    @State private var nearbyState: NearbyLoadState = .loading
    @State private var selectedNearbyRide: NearbyRide? = nil
    @State private var recentRides: [HistoryRide] = []
    @State private var recentLoading = true
    @State private var selectedHistoryRide: HistoryRide? = nil
    @State private var homeCardSnoozed = UpsellState.isHomeCardSnoozed()

    // Nearby Rides discovery is temporarily hidden on the client. Backend support
    // stays fully intact — flip this to `true` to re-enable the entire section.
    private let showNearbyRides = false

    var body: some View {
        NavigationStack(path: $navPath) {
            homeRoot
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .createRide: CreateRideView()
                    case .rideLobby:  RideLobbyView()
                    }
                }
        }
        .onChange(of: appState.currentRideId) { _, newId in
            guard newId != nil else { return }
            navPath = NavigationPath([HomeRoute.rideLobby])
        }
        .onReceive(NotificationCenter.default.publisher(for: .convotrackOpenRide)) { note in
            guard let id = note.userInfo?["rideId"] as? String else { return }
            DeepLinkRouter.pendingOpenRideId = nil
            openRideNavigation(id)
        }
        .onAppear {
            homeCardSnoozed = UpsellState.isHomeCardSnoozed()
            // Cold launch from the Live Activity: the link arrived before this view listened.
            if let id = DeepLinkRouter.pendingOpenRideId {
                DeepLinkRouter.pendingOpenRideId = nil
                openRideNavigation(id)
            }
        }
        .onChange(of: appState.popToRoot) { _, shouldPop in
            if shouldPop {
                navPath = NavigationPath()
                appState.popToRoot = false
            }
        }
    }

    /// Live Activity tap. Only the ride the rider is currently in is honoured; an unknown or ended
    /// ride is ignored. The lobby pushes navigation itself once the ride is loaded and ACTIVE.
    private func openRideNavigation(_ rideId: String) {
        guard appState.currentRideId == rideId else { return }
        activeTab = .home
        appState.openNavigationRideId = rideId
        // Already inside the ride (lobby or navigation on the stack): leave the stack alone.
        if navPath.isEmpty { navPath.append(HomeRoute.rideLobby) }
    }

    private var homeRoot: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                DSScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(topInset: proxy.safeAreaInsets.top)

                        if showNearbyRides {
                            // Hidden on the client for now (see `showNearbyRides`).
                            VStack(spacing: DS.Space.listGap) {
                                nearbyContent
                            }
                            .padding(.horizontal, DS.Space.screenInset)
                            .padding(.top, 28)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                if let card = homeCard {
                                    DSPromoBanner(
                                        eyebrow: "ConvoTrack Pro",
                                        message: card.message,
                                        actionTitle: card.actionTitle,
                                        onDismiss: card.dismissible ? { dismissHomeCard() } : nil
                                    ) { paywall.present(.homeCard) }
                                    .padding(.bottom, DS.Space.sectionGap)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                                if appState.currentRideId != nil {
                                    ActiveRideSection(
                                        ride: appState.currentRide,
                                        rideId: appState.currentRideId,
                                        onTap: { navPath.append(HomeRoute.rideLobby) },
                                        onRideLoaded: { appState.currentRide = $0 },
                                        onRideClear:  { appState.currentRideId = nil }
                                    )
                                    .padding(.bottom, DS.Space.sectionGap)
                                }
                                recentRidesSection
                            }
                            .padding(.horizontal, DS.Space.screenInset)
                            .padding(.top, 28)
                            .padding(.bottom, DS.Space.sectionGap)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                // The hero photo runs under the status bar; its content is inset below the nav bar.
                .ignoresSafeArea(edges: .top)
                .refreshable { showNearbyRides ? await loadNearby() : await loadRecent() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PlanBadgeButton(source: .homeBadge)
            }
            .sharedBackgroundVisibility(.hidden)
            // The connection indicator only means something while a ride session exists.
            if appState.currentRideId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    DSConnectionStatusButton(state: connectionState)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationDestination(item: $selectedHistoryRide) { ride in
            RideSummaryView(rideId: ride.rideId, rideTitle: ride.title, fallback: ride)
        }
        .task {
            if showNearbyRides {
                await loadNearby()
            } else {
                await loadRecent()
            }
        }
        .sheet(item: $selectedNearbyRide) { ride in
            RidePreviewSheet(ride: ride)
                .environmentObject(appState)
        }
    }

    // MARK: - Home Pro card

    private struct HomeCard {
        let message: LocalizedStringKey
        let actionTitle: LocalizedStringKey
        let dismissible: Bool
    }

    /// One quiet card under the hero. The trial countdown leads; the last day can't be hidden,
    /// everything else can be snoozed. Never during a ride, for Pro, or once the trial has ended.
    private var homeCard: HomeCard? {
        guard appState.currentRideId == nil else { return nil }
        switch membershipStore.access {
        case .pro:
            return nil
        case .trial:
            if let days = membershipStore.trialDaysLeft, days > 1 {
                guard !homeCardSnoozed else { return nil }
                return HomeCard(message: "\(days) days left in your free trial", actionTitle: "Go Pro", dismissible: true)
            }
            return HomeCard(message: "Your free trial ends today", actionTitle: "Go Pro", dismissible: false)
        case .trialExpired:
            // The locked buttons, the badge and the app-open nudge already carry this state; a
            // fourth upsell on the same screen is noise (design review).
            return nil
        case .free:
            guard !homeCardSnoozed else { return nil }
            return HomeCard(message: "Bigger packs and no monthly ride limit", actionTitle: "Go Pro", dismissible: true)
        }
    }

    private func dismissHomeCard() {
        PaywallAnalytics.log(.homeCardDismissed, source: .homeCard, access: membershipStore.access)
        if case .trial = membershipStore.access {
            UpsellState.snoozeHomeCard(inTrial: true)
        } else {
            UpsellState.snoozeHomeCard(inTrial: false)
        }
        withAnimation(DS.Motion.emphasized) { homeCardSnoozed = true }
    }

    private var connectionState: DSConnectionState {
        switch rideSession.connectionState {
        case .connected: .connected
        case .reconnecting: .reconnecting
        case .disconnected: .offline
        }
    }

    /// Riders photo, headline and the CREATE / JOIN pair. The photo fades into the base.
    private func hero(topInset: CGFloat) -> some View {
        // The photo is a background, so the hero grows with the text instead of clipping it at
        // large Dynamic Type sizes.
        VStack(alignment: .leading, spacing: 0) {
            DSHeroTitleBlock(
                eyebrow: "Ride together",
                title: "Discover new roads",
                subtitle: "Plan, join and track rides with your tribe."
            )
            DSActionButtonPair(
                createAction: {
                    if membershipStore.mustUpgradeToRide { paywall.present(.createBlocked) }
                    else { navPath.append(HomeRoute.createRide) }
                },
                joinAction: {
                    if membershipStore.mustUpgradeToRide { paywall.present(.joinBlocked) }
                    else { showJoinRide = true }
                },
                isLocked: membershipStore.mustUpgradeToRide
            )
            .padding(.top, 22)
        }
        .padding(.horizontal, DS.Space.screenInset)
        .padding(.top, topInset + 24)
        .padding(.bottom, DS.Space.p5)
        .frame(maxWidth: .infinity, minHeight: topInset + 250, alignment: .bottomLeading)
        .background { DSHeroPhoto(imageName: "hero_riders_sunset_mirrored", height: nil, sideFade: true) }
    }

    // MARK: - Nearby content states

    @ViewBuilder
    private var nearbyContent: some View {
        switch nearbyState {
        case .loading:
            ProgressView()
                .tint(DS.Accent.base)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

        case .locationDenied:
            NearbyEmptyCard(
                icon: "location.slash.fill",
                title: "Location access needed",
                subtitle: "Enable location to discover rides starting near you.",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                actionLabel: "Open Settings"
            )

        case .error:
            NearbyEmptyCard(
                icon: "wifi.slash",
                title: "Couldn't load rides",
                subtitle: "Check your connection and try again.",
                action: { Task { await loadNearby() } },
                actionLabel: "Retry"
            )

        case .loaded:
            if displayedNearbyRides.isEmpty {
                NearbyEmptyCard(
                    icon: "road.lanes",
                    title: "No rides nearby",
                    subtitle: "No rides starting within 20 km. Be the first to plan one!",
                    action: { navPath.append(HomeRoute.createRide) },
                    actionLabel: "Create Ride"
                )
            } else {
                ForEach(displayedNearbyRides) { ride in
                    NearbyRideCard(ride: ride)
                        .onTapGesture { handleNearbyTap(ride) }
                }
            }
        }
    }

    // Hide the ride already surfaced in the Active Ride card to avoid duplication.
    private var displayedNearbyRides: [NearbyRide] {
        nearbyRides.filter { $0.id != appState.currentRideId }
    }

    private func handleNearbyTap(_ ride: NearbyRide) {
        // Never show the join sheet for a ride I already belong to. Check both the
        // server-provided viewerRole AND my leader id directly, so a leader is routed
        // to the lobby even if viewerRole is missing/stale (e.g. pre-deploy backend).
        let myId = clerk.user?.id
        let iAmLeader = myId != nil && ride.leaderId == myId
        if ride.isParticipant || iAmLeader {
            appState.inviteCode = ride.inviteCode
            appState.currentRideId = ride.id   // triggers onChange → pushes RideLobbyView
        } else {
            selectedNearbyRide = ride
        }
    }

    // MARK: - Load nearby

    private func loadNearby() async {
        nearbyState = .loading
        let authStatus = CLLocationManager().authorizationStatus
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            nearbyState = .locationDenied
            return
        }
        let loc: CLLocation? = await withCheckedContinuation { cont in
            LocationService.shared.requestCurrentLocation { cont.resume(returning: $0) }
        }
        guard let loc else { nearbyState = .error; return }
        do {
            nearbyRides = try await APIClient.shared.getNearbyRides(
                lat: loc.coordinate.latitude,
                lng:  loc.coordinate.longitude
            )
            nearbyState = .loaded
        } catch {
            nearbyState = .error
        }
    }

    // MARK: - Recent rides

    // Show the most recent rides; skip the one already surfaced in the Active Ride card.
    private var displayedRecentRides: [HistoryRide] {
        recentRides
            .filter { $0.rideId != appState.currentRideId }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var recentRidesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading(title: "Recent rides") {
                if !displayedRecentRides.isEmpty {
                    DSSectionAction(title: "See all") { activeTab = .history }
                }
            }
            if recentLoading {
                DSLoadingState()
            } else if displayedRecentRides.isEmpty {
                DSEmptyState(
                    systemImage: "flag.checkered",
                    title: "No rides yet",
                    message: "Your rides will show up here once you create or join your first ride.",
                    actionTitle: "Create ride",
                    action: { navPath.append(HomeRoute.createRide) }
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(displayedRecentRides) { ride in
                        Button { handleRecentTap(ride) } label: { RideRow(ride: ride) }
                            .buttonStyle(.plain)
                    }
                }
                // Rows break out to a 12 pt inset (headings stay at 20) so a ride name, its facts
                // and RESUME all fit on a 402 pt screen.
                .padding(.horizontal, -(DS.Space.screenInset - DS.Space.p3))
            }
        }
    }

    private func handleRecentTap(_ ride: HistoryRide) {
        if ride.status == "COMPLETED" {
            selectedHistoryRide = ride
        } else {
            if let code = ride.inviteCode { appState.inviteCode = code }
            appState.currentRideId = ride.rideId   // triggers onChange → pushes RideLobbyView
        }
    }

    private func loadRecent() async {
        recentRides = (try? await APIClient.shared.getMyRides(
            statuses: APIClient.RideStatusFilter.inProgress
        )) ?? []
        recentLoading = false
    }
}

// MARK: - Nearby Ride Card

struct NearbyRideCard: View {
    let ride: NearbyRide

    var body: some View {
        HStack(spacing: 14) {
            // Icon column
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ride.isLive ? DS.Accent.base.opacity(0.12) : DS.Surface.raised)
                    .frame(width: 52, height: 52)
                Image(systemName: ride.isLive ? "location.fill.viewfinder" : "road.lanes")
                    .font(.system(size: 22))
                    .foregroundColor(ride.isLive ? DS.Accent.base : DS.Text.secondary.base)
            }

            // Text column
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(ride.title)
                        .dsText(.input)
                        .fontWeight(.bold)
                        .foregroundColor(DS.Text.primary.base)
                        .lineLimit(1)
                    Spacer()
                    if ride.isMine {
                        BadgeChip(text: "YOURS", fg: DS.Text.onAccent, bg: DS.Accent.base)
                    } else if ride.isJoined {
                        BadgeChip(text: "JOINED", fg: DS.Text.onAccent, bg: DS.Status.success)
                    } else {
                        StatusBadge(isLive: ride.isLive)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Accent.base)
                    Text(ride.destinationName)
                        .dsText(.badge)
                        .foregroundColor(DS.Text.secondary.base)
                        .lineLimit(1)
                    Text("·")
                        .foregroundColor(DS.Text.secondary.base.opacity(0.5))
                    Text(ride.formattedRideDistance)
                        .dsText(.badge)
                        .foregroundColor(DS.Text.secondary.base)
                }
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Text.secondary.base.opacity(0.6))
                    Text("\(ride.riderCount) rider\(ride.riderCount == 1 ? "" : "s")")
                        .dsText(.dataMono)
                        .foregroundColor(DS.Text.secondary.base)
                    Text("·")
                        .foregroundColor(DS.Text.secondary.base.opacity(0.5))
                    Text(ride.formattedUserDistance)
                        .dsText(.dataMono)
                        .foregroundColor(DS.Text.secondary.base)
                    if ride.isFull {
                        Text("· FULL")
                            .dsText(.badge)
                            .foregroundColor(DS.Status.danger.opacity(0.8))
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Text.secondary.base.opacity(0.5))
        }
        .padding(14)
        .background(DS.Background.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ride.isLive ? DS.Accent.base.opacity(0.25) : DS.Border.strongColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let isLive: Bool

    var body: some View {
        BadgeChip(
            text: isLive ? "LIVE" : "FORMING",
            fg: isLive ? DS.Text.onAccent : Color(red: 0.15, green: 0.10, blue: 0),
            bg: isLive ? DS.Accent.base : Color(red: 1.0, green: 0.78, blue: 0.25)
        )
    }
}

private struct BadgeChip: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        Text(text)
            .dsText(.badge)
            .tracking(1)
            .foregroundColor(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }
}

// MARK: - Nearby Empty Card

private struct NearbyEmptyCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(DS.Text.secondary.base.opacity(0.5))
            VStack(spacing: 6) {
                Text(title)
                    .dsText(.input).fontWeight(.semibold)
                    .foregroundColor(DS.Text.primary.base)
                Text(subtitle)
                    .dsText(.body)
                    .foregroundColor(DS.Text.secondary.base)
                    .multilineTextAlignment(.center)
            }
            Button(action: action) {
                Text(actionLabel)
                    .dsText(.badge).tracking(1)
                    .foregroundColor(DS.Text.onAccent)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(DS.Accent.base)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .background(DS.Background.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Border.strongColor.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Ride Preview Sheet

struct RidePreviewSheet: View {
    let ride: NearbyRide
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isJoining = false
    @State private var joinError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Background.base.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Status + title block
                        VStack(alignment: .leading, spacing: 10) {
                            StatusBadge(isLive: ride.isLive)
                            Text(ride.title)
                                .dsText(.heroTitleCompact)
                                .foregroundColor(DS.Text.primary.base)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 28)

                        // Info rows
                        VStack(spacing: 0) {
                            infoRow(icon: "mappin.circle.fill",   label: "Destination",    value: ride.destinationName)
                            divider
                            infoRow(icon: "road.lanes",            label: "Ride distance",  value: ride.formattedRideDistance)
                            divider
                            infoRow(icon: "person.2.fill",         label: "Riders",         value: "\(ride.riderCount) / \(ride.maxParticipants)")
                            divider
                            infoRow(icon: "crown.fill",            label: "Led by",         value: ride.leaderName)
                            divider
                            infoRow(icon: "location.fill",         label: "Starts",         value: ride.formattedUserDistance)
                        }
                        .background(DS.Background.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Border.strongColor.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 20)

                        // Error
                        if let err = joinError {
                            Text(err)
                                .dsText(.body)
                                .foregroundColor(DS.Status.danger)
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }

                        // Join CTA
                        VStack(spacing: 8) {
                            Button(action: { Task { await join() } }) {
                                Group {
                                    if isJoining {
                                        ProgressView().tint(DS.Text.onAccent)
                                    } else {
                                        Text(ride.isFull ? "RIDE IS FULL" : "JOIN RIDE")
                                            .dsText(.badge).tracking(1)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(ride.isFull ? DS.Surface.neutralBadge : DS.Accent.base)
                                .foregroundColor(ride.isFull ? DS.Text.secondary.base : DS.Text.onAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isJoining || ride.isFull)

                            Text("You'll join as a Formation Rider")
                                .dsText(.badge)
                                .foregroundColor(DS.Text.secondary.base)
                                .tracking(1)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 36)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.Text.secondary.base)
                            .frame(width: 30, height: 30)
                            .background(DS.Surface.raised)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Border.strongColor.opacity(0.3))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(DS.Accent.base)
                .frame(width: 22)
            Text(label)
                .dsText(.body)
                .foregroundColor(DS.Text.secondary.base)
            Spacer()
            Text(value)
                .dsText(.body).fontWeight(.medium)
                .foregroundColor(DS.Text.primary.base)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func join() async {
        joinError = nil
        isJoining = true
        do {
            try await APIClient.shared.joinRide(ride.id)
            appState.currentRideId = ride.id
            appState.inviteCode = ride.inviteCode
            dismiss()
        } catch APIClientError.serverError(let msg) {
            joinError = friendlyError(msg)
        } catch {
            joinError = "Something went wrong. Please try again."
        }
        isJoining = false
    }

    private func friendlyError(_ code: String) -> String {
        switch code {
        case "RIDE_FULL":       return "This ride is already full."
        case "QUOTA_EXCEEDED":  return "You've reached your monthly ride limit."
        case "ALREADY_JOINED":  return "You're already part of this ride."
        case "RIDE_NOT_ACTIVE": return "This ride is no longer accepting riders."
        default:                return "Couldn't join: \(code)"
        }
    }
}

// MARK: - Active Ride Section

struct ActiveRideSection: View {
    let ride: Ride?
    let rideId: String?
    let onTap: () -> Void
    let onRideLoaded: (Ride) -> Void
    let onRideClear: () -> Void

    /// appVocabulary: IN LOBBY / RIDING (LIVE while the ride isn't loaded yet).
    private var statusLabel: LocalizedStringKey {
        switch ride?.status {
        case "ACTIVE", "IN_PROGRESS": return "Riding"
        case "LOBBY":  return "In lobby"
        default:       return "Live"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading(title: "Active ride") {
                DSLiveIndicator(title: statusLabel)
            }
            Button(action: onTap) { ActiveRideCard(ride: ride) }
                .buttonStyle(.plain)
        }
        .task {
            guard ride == nil, let id = rideId else { return }
            do {
                let loaded = try await APIClient.shared.getRide(id)
                if loaded.status == "COMPLETED" || loaded.status == "ENDED" {
                    onRideClear()
                } else {
                    onRideLoaded(loaded)
                }
            } catch APIClientError.serverError(let code) where APIClient.isNotFound(code) {
                // The ride is genuinely gone (deleted server-side): clearing is correct.
                onRideClear()
            } catch {
                // Everything else — offline, a 5xx, an expired token, or this `.task` simply
                // being cancelled because the card was torn down mid-flight — says nothing about
                // whether the ride still exists. Clearing on those wiped the PERSISTED active
                // ride: `currentRideId`'s didSet also nils `currentRide`, so the rider lost the
                // Active Ride card entirely and the ride reappeared under RECENT RIDES, while any
                // lobby already on screen went blank. Leave the id alone; the card keeps its
                // placeholder and the lobby's own retrying fetch is the recovery path.
            }
        }
    }
}

struct ActiveRideCard: View {
    let ride: Ride?

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraCommand: MapCameraCommand? = nil
    @State private var heroPhase: DestinationHeroPhase = .resolving

    private var attribution: String? {
        if case .photo(let photo) = heroPhase { return photo.attribution }
        return nil
    }

    private var riders: [DSAvatarStack.Item] {
        (ride?.participants ?? []).map {
            DSAvatarStack.Item(id: $0.userId, name: $0.name, imageURL: $0.avatarUrl.flatMap(URL.init(string:)))
        }
    }

    var body: some View {
        DSActiveRideCard(
            title: ride?.title ?? String(localized: "Loading…"),
            destination: ride?.destinationName,
            distance: ride.flatMap { $0.distanceMeters > 0 ? String(format: "%.1f km", $0.distanceMeters / 1000) : nil },
            time: ride.flatMap { $0.estimatedDurationSeconds > 0 ? RideDuration.inline($0.estimatedDurationSeconds) : nil },
            riders: riders,
            attribution: attribution
        ) {
            heroLayer
        }
        .task(id: destinationPhotoKey) { await loadDestinationPhoto() }
        .animation(.easeInOut(duration: 0.35), value: heroPhase)
    }

    /// Fixed-size container owns the layout; the photo is decoration inside it. Sizing the Image
    /// directly would let its aspect ratio set the card's WIDTH (a panorama at 200pt tall reports
    /// ~600pt), which widens the whole home feed. `scaledToFill` because this slot is a landscape
    /// banner close to the 16:9 photos Places serves, under a dark scrim as texture.
    @ViewBuilder
    private var heroLayer: some View {
        switch heroPhase {
        case .resolving:
            // We don't yet know whether there's a photo; showing the map here would only be
            // replaced a moment later.
            LinearGradient(colors: [DS.Surface.raised, DS.Background.base], startPoint: .topLeading, endPoint: .bottomTrailing)

        case .photo(let photo):
            Color.clear
                .overlay(Image(uiImage: photo.image).resizable().scaledToFill())
                .clipped()

        case .unavailable:
            if let ride, !ride.waypoints.isEmpty {
                let destPin = MapPin(
                    id: "dest",
                    coordinate: CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng),
                    style: .simpleDot(color: UIColor(DS.Accent.base), size: 10),
                    anchorBottom: false
                )
                // Route only computed in this branch, so a card showing a photo skips the
                // Directions work entirely.
                GoogleMapView(routeCoords: routeCoordinates, pins: [destPin], cameraCommand: cameraCommand, isInteractive: false)
                    .allowsHitTesting(false)
                    .task(id: ride.id) { await computeRoute(ride) }
            } else {
                LinearGradient(colors: [DS.Surface.raised, DS.Background.base], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    /// Identity of the destination whose photo this card wants. Empty until the ride is loaded,
    /// and includes the ride id so a switched ride can't keep showing the previous photo.
    private var destinationPhotoKey: String {
        guard let ride, !ride.destinationName.isEmpty else { return "" }
        return "\(ride.id)|\(ride.destinationName)|\(ride.destinationLat),\(ride.destinationLng)"
    }

    /// Goes through the same `GooglePlacePhotoService` singleton as the lobby, so whichever
    /// screen asks first pays for the two API calls and the other is served from the shared
    /// memory/disk cache — the service keys on destination name + coordinate, not on the caller.
    private func loadDestinationPhoto() async {
        let key = destinationPhotoKey
        guard !key.isEmpty, let ride else {
            heroPhase = .resolving
            return
        }
        heroPhase = .resolving
        let fetched = await GooglePlacePhotoService.shared.photo(
            destinationName: ride.destinationName,
            coordinate: CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng)
        )
        guard !Task.isCancelled, key == destinationPhotoKey else { return }
        heroPhase = fetched.map { .photo($0) } ?? .unavailable
    }

    @MainActor
    private func computeRoute(_ ride: Ride) async {
        // Prefer the leader-selected route geometry stored on the ride.
        if let stored = GoogleDirectionsService.decodedRoute(ride.routePolyline) {
            routeCoordinates = stored
            cameraCommand = MapCameraCommand.fitRoute(stored, padding: 48)
            return
        }
        let sorted = ride.waypoints.sorted { $0.order < $1.order }
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
        if !allCoords.isEmpty { cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 48) }
    }
}

#Preview {
    HomeView(activeTab: .constant(.home), showJoinRide: .constant(false))
        .environmentObject(AppState())
        .environmentObject(RideRealtimeSession())
        .environmentObject(MembershipStore())
        .environmentObject(PaywallPresenter())
}
