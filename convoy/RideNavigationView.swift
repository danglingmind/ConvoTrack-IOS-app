import SwiftUI
import MapKit
import ClerkKit
import Combine

// MARK: - Display Models

struct LiveRider: Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let rank: Int
    let distanceToGoalKm: Double
    let speedKmh: Double
    let coordinate: CLLocationCoordinate2D
    let isMe: Bool
}

struct NavLeaderboardRow: Identifiable {
    let id: String
    let rank: Int
    let name: String
    let avatarUrl: String?
    let distanceToGoalKm: Double
    let isMe: Bool
}

// MARK: - NavigationViewModel

@MainActor
final class NavigationViewModel: ObservableObject, LocationServiceDelegate {
    @Published var riders: [LiveRider] = []
    @Published var leaderboardRows: [NavLeaderboardRow] = []
    @Published var mySpeedKmh: Double = 0
    @Published var myRank: Int = 0
    @Published var myDistanceToGoalKm: Double = 0
    @Published var riderCount: Int = 0
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var routeVersion: Int = 0   // increments when route is ready; Equatable
    @Published var destinationCoordinate: CLLocationCoordinate2D? = nil
    @Published var startCoordinate: CLLocationCoordinate2D? = nil
    @Published var middleWaypoints: [Waypoint] = []
    @Published var locationTick: Int = 0   // increments each update, triggers camera onChange
    @Published var userHeading: Double = 0
    private(set) var userLocation: CLLocationCoordinate2D? = nil
    @Published var showSplitAlert = false
    @Published var showSummary = false
    @Published var isEnding = false
    @Published var endError: String? = nil
    @Published var currentInstruction: String = ""
    @Published var distanceToNextTurnMeters: Double = 0

    var amILeader: Bool { !myUserId.isEmpty && myUserId == leaderId }

    var etaString: String {
        guard routeExpectedTravelTime > 0, totalDistanceMeters > 0, myDistanceToGoalKm >= 0 else { return "--:--" }
        let remainingFraction = (myDistanceToGoalKm * 1000) / totalDistanceMeters
        let remainingSecs = routeExpectedTravelTime * max(0, remainingFraction)
        let arrival = Date().addingTimeInterval(remainingSecs)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: arrival)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private struct NavStep {
        let instruction: String
        let endCoordinate: CLLocationCoordinate2D
        let distanceMeters: Double
    }

    private var rideId = ""
    private var staticParticipants: [RideParticipant] = []
    private var myUserId = ""
    private var leaderId = ""
    private var totalDistanceMeters: Double = 0
    private var routeExpectedTravelTime: TimeInterval = 0
    private var navSteps: [NavStep] = []
    private var currentStepIndex: Int = 0
    private var lastBroadcastDate: Date = .distantPast
    private var lastCameraTickDate: Date = .distantPast

    func setup(rideId: String, ride: Ride, myUserId: String) async {
        self.rideId = rideId
        self.staticParticipants = ride.participants
        self.myUserId = myUserId
        self.leaderId = ride.leaderId
        self.totalDistanceMeters = ride.distanceMeters

        let sorted = ride.waypoints.sorted { $0.order < $1.order }
        if let dest = sorted.last {
            destinationCoordinate = CLLocationCoordinate2D(latitude: dest.lat, longitude: dest.lng)
        }
        if let start = sorted.first {
            startCoordinate = CLLocationCoordinate2D(latitude: start.lat, longitude: start.lng)
        }
        middleWaypoints = sorted.filter { $0.type == "WAYPOINT" }

        // Pre-populate leaderboard so it shows immediately before any socket updates
        let active = ride.participants.filter { $0.status != "LEFT" }
        leaderboardRows = active.enumerated().map { index, p in
            NavLeaderboardRow(
                id: p.userId, rank: index + 1, name: p.name,
                avatarUrl: p.avatarUrl,
                distanceToGoalKm: ride.distanceMeters / 1000,
                isMe: p.userId == myUserId
            )
        }
        riderCount = active.count
        if let myRow = leaderboardRows.first(where: { $0.isMe }) {
            myRank = myRow.rank
            myDistanceToGoalKm = ride.distanceMeters / 1000
        }

        await calculateRoute(from: ride.waypoints)

        let socket = SocketClient.shared
        socket.onStateUpdate = { [weak self] update in self?.handleStateUpdate(update) }
        socket.onSplitDetected = { [weak self] _ in self?.showSplitAlert = true }
        socket.onSplitResolved = { [weak self] in self?.showSplitAlert = false }

        // Re-join room so the server sends the current state snapshot to this client
        // and so state updates are received after any socket reconnect.
        socket.joinRoom(rideId: rideId)

        LocationService.shared.delegate = self
        LocationService.shared.requestPermission()
        LocationService.shared.start()
    }

    func teardown() {
        LocationService.shared.stop()
        LocationService.shared.delegate = nil
        SocketClient.shared.onStateUpdate = nil
        SocketClient.shared.onSplitDetected = nil
        SocketClient.shared.onSplitResolved = nil
    }

    func endRide() async {
        isEnding = true
        endError = nil
        do {
            try await APIClient.shared.endRide(rideId)
            showSummary = true
        } catch {
            endError = error.localizedDescription
        }
        isEnding = false
    }

    func broadcastRegroup(reason: CoordinationOverlayView.RegroupReason?) {
        guard let reason, let loc = LocationService.shared.lastLocation else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        if reason.isEmergency {
            SocketClient.shared.emitEmergency(rideId: rideId, lat: lat, lng: lng, message: "Emergency")
        } else {
            let type = reason.rawValue.uppercased().replacingOccurrences(of: " ", with: "_")
            SocketClient.shared.emitRegroup(rideId: rideId, type: type, lat: lat, lng: lng)
        }
    }

    // MARK: - LocationServiceDelegate

    func locationService(_ service: LocationService, didUpdate location: CLLocation, battery: Double, signalStrength: String) {
        mySpeedKmh = max(0, location.speed * 3.6)
        userLocation = location.coordinate
        if location.course >= 0 { userHeading = location.course }
        updateCurrentStep(location: location)

        let now = Date()
        // Cap camera updates at ~10 Hz so overlapping animations don't jam the map
        if now.timeIntervalSince(lastCameraTickDate) >= 0.1 {
            lastCameraTickDate = now
            locationTick += 1
        }

        guard now.timeIntervalSince(lastBroadcastDate) >= 2.0 else { return }
        lastBroadcastDate = now
        SocketClient.shared.emitLocationUpdate(
            rideId: rideId,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: location.speed,
            heading: location.course,
            battery: battery,
            signalStrength: signalStrength
        )
    }

    // MARK: - Private

    private func handleStateUpdate(_ update: RideStateUpdate) {
        riderCount = update.participants.count

        // Only overwrite the pre-populated leaderboard when the server actually has data.
        // The initial ride:state_update emitted on start has leaderboard: [] before any
        // location updates have been processed — don't let that clear what we pre-seeded.
        if !update.leaderboard.isEmpty {
            leaderboardRows = update.leaderboard.map { entry in
                let participant = staticParticipants.first { $0.userId == entry.userId }
                let distKm = max(0, (totalDistanceMeters - entry.progress) / 1000)
                return NavLeaderboardRow(
                    id: entry.userId, rank: entry.rank, name: entry.name,
                    avatarUrl: participant?.avatarUrl,
                    distanceToGoalKm: distKm,
                    isMe: entry.userId == myUserId
                )
            }
        }

        riders = update.participants.compactMap { live in
            guard let lat = live.lat, let lng = live.lng else { return nil }
            let participant = staticParticipants.first { $0.userId == live.userId }
            let lbEntry = update.leaderboard.first { $0.userId == live.userId }
            let distKm = max(0, (totalDistanceMeters - live.progress) / 1000)
            return LiveRider(
                id: live.userId,
                name: participant?.name ?? lbEntry?.name ?? "Rider",
                avatarUrl: participant?.avatarUrl,
                rank: lbEntry?.rank ?? 99,
                distanceToGoalKm: distKm,
                speedKmh: (live.speed ?? 0) * 3.6,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                isMe: live.userId == myUserId
            )
        }

        if let myEntry = update.leaderboard.first(where: { $0.userId == myUserId }) {
            myRank = myEntry.rank
            myDistanceToGoalKm = max(0, (totalDistanceMeters - myEntry.progress) / 1000)
        }

        if update.status == "COMPLETED" { showSummary = true }
    }

    private func calculateRoute(from waypoints: [Waypoint]) async {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }
        let items = sorted.map {
            MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)))
        }
        var allCoords: [CLLocationCoordinate2D] = []
        var totalTime: TimeInterval = 0
        var steps: [NavStep] = []
        for i in 0..<items.count - 1 {
            let req = MKDirections.Request()
            req.source = items[i]; req.destination = items[i + 1]; req.transportType = .automobile
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                let coords = route.polyline.coordinates
                allCoords += (i == 0) ? coords : Array(coords.dropFirst())
                totalTime += route.expectedTravelTime
                for step in route.steps {
                    let instr = step.instructions.trimmingCharacters(in: .whitespaces)
                    guard !instr.isEmpty, let end = step.polyline.coordinates.last else { continue }
                    steps.append(NavStep(instruction: instr, endCoordinate: end, distanceMeters: step.distance))
                }
            }
        }
        navSteps = steps
        currentStepIndex = 0
        if let first = navSteps.first {
            currentInstruction = first.instruction
            distanceToNextTurnMeters = first.distanceMeters
        }
        routeCoordinates = allCoords
        routeExpectedTravelTime = totalTime
        routeVersion += 1
    }

    private func updateCurrentStep(location: CLLocation) {
        guard currentStepIndex < navSteps.count else { return }
        let step = navSteps[currentStepIndex]
        let endLoc = CLLocation(latitude: step.endCoordinate.latitude, longitude: step.endCoordinate.longitude)
        distanceToNextTurnMeters = location.distance(from: endLoc)
        if distanceToNextTurnMeters < 30, currentStepIndex + 1 < navSteps.count {
            currentStepIndex += 1
            currentInstruction = navSteps[currentStepIndex].instruction
        }
    }
}

// MARK: - Main View

struct RideNavigationView: View {
    let rideId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Clerk.self) private var clerk
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = NavigationViewModel()

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRiderId: String? = nil
    @State private var showRegroup = false
    @State private var regroupReason: CoordinationOverlayView.RegroupReason? = nil
    @State private var showEndError = false

    private var destinationName: String { appState.currentRide?.destinationName ?? "Destination" }

    private var navCameraDistance: Double {
        switch vm.mySpeedKmh {
        case ..<20:  return 300
        case ..<60:  return 500
        default:     return 800
        }
    }

    var body: some View {
        ZStack {
            mapLayer
            hudLayer
            rightStatPills
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear { appState.isRideActive = true }
        .onDisappear {
            appState.isRideActive = false
            vm.teardown()
        }
        .task { await loadAndSetup() }
        .onChange(of: vm.routeVersion) { _, _ in
            // Show full route overview until the first location update arrives
            guard vm.locationTick == 0 else { return }
            if !vm.routeCoordinates.isEmpty {
                let poly = MKPolyline(coordinates: vm.routeCoordinates, count: vm.routeCoordinates.count)
                let rect = poly.boundingMapRect
                cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15))
            } else if let dest = vm.destinationCoordinate {
                cameraPosition = .region(MKCoordinateRegion(
                    center: dest,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                ))
            }
        }
        .onChange(of: vm.locationTick) { old, new in
            guard let coord = vm.userLocation else { return }
            let isFirstFix = old == 0
            withAnimation(isFirstFix ? .easeInOut(duration: 1.5) : .linear(duration: 0.3)) {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: coord,
                    distance: navCameraDistance,
                    heading: vm.userHeading,
                    pitch: 55
                ))
            }
        }
        .sheet(isPresented: $showRegroup) {
            RegroupBottomSheet(
                selectedReason: $regroupReason,
                onBroadcast: {
                    vm.broadcastRegroup(reason: regroupReason)
                    showRegroup = false
                },
                isBroadcasting: false
            )
            .presentationDetents([.large])
        }
        .navigationDestination(isPresented: $vm.showSummary) {
            RideSummaryView(rideId: rideId, rideTitle: appState.currentRide?.title, isPostRide: true)
        }
        .alert("Couldn't End Ride", isPresented: $showEndError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.endError ?? "An error occurred.")
        }
        .onChange(of: vm.endError) { _, err in
            if err != nil { showEndError = true }
        }
    }

    // MARK: - Load

    private func loadAndSetup() async {
        let fetched = try? await APIClient.shared.getRide(rideId)
        let ride = fetched ?? appState.currentRide
        if let fetched { appState.currentRide = fetched }
        guard let ride else { return }
        let userId = clerk.user?.id ?? ""
        await vm.setup(rideId: rideId, ride: ride, myUserId: userId)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $cameraPosition, content: mapContent)
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
    }

    @MapContentBuilder
    private func mapContent() -> some MapContent {
        routePolyline
        riderAnnotations
        waypointAnnotations
    }

    @MapContentBuilder
    private var routePolyline: some MapContent {
        if !vm.routeCoordinates.isEmpty {
            MapPolyline(coordinates: vm.routeCoordinates)
                .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var riderAnnotations: some MapContent {
        ForEach(vm.riders.filter { !$0.isMe }) { rider in
            Annotation(rider.name, coordinate: rider.coordinate, anchor: .bottom) {
                LiveRiderPin(rider: rider, isSelected: selectedRiderId == rider.id)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedRiderId = (selectedRiderId == rider.id) ? nil : rider.id
                        }
                    }
            }
        }
    }

    @MapContentBuilder
    private var waypointAnnotations: some MapContent {
        if let coord = vm.startCoordinate {
            Annotation("", coordinate: coord, anchor: .center) { StartPin() }
        }
        ForEach(vm.middleWaypoints, id: \.order) { wp in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                WaypointPin(name: wp.name)
            }
        }
        if let coord = vm.destinationCoordinate {
            Annotation("", coordinate: coord, anchor: .bottom) { DestinationPin(name: destinationName) }
        }
        if let coord = vm.userLocation {
            Annotation("", coordinate: coord, anchor: .center) { NavUserArrow() }
        }
    }

    // MARK: - HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            topBar

            if vm.showSplitAlert {
                GroupSplitAlert(
                    onIgnore: { withAnimation(.spring()) { vm.showSplitAlert = false } },
                    onRegroup: { showRegroup = true }
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(), value: vm.showSplitAlert)
            }

            Spacer()
            bottomControls
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Button(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.onSurface)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.primaryFixed)
                        Text(vm.myRank > 0 ? "RANK \(vm.myRank)" : "RANK --")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))

                    HStack(spacing: 7) {
                        Circle().fill(Color.primaryFixed).frame(width: 7, height: 7)
                            .shadow(color: Color.primaryFixed, radius: 5)
                        Text(vm.riderCount > 0 ? "\(vm.riderCount) RIDERS LIVE" : "-- RIDERS LIVE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)

            turnBanner
            leaderboardStrip
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var turnBanner: some View {
        if !vm.currentInstruction.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: maneuverIcon(for: vm.currentInstruction))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.primaryFixed.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primaryFixed.opacity(0.4), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.currentInstruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.onSurface)
                        .lineLimit(2)

                    if vm.distanceToNextTurnMeters > 0 {
                        Text(vm.distanceToNextTurnMeters >= 1000
                             ? String(format: "in %.1f km", vm.distanceToNextTurnMeters / 1000)
                             : String(format: "in %.0f m", vm.distanceToNextTurnMeters))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.primaryFixed)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.25), lineWidth: 1))
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: vm.currentInstruction)
        }
    }

    private func maneuverIcon(for instruction: String) -> String {
        let l = instruction.lowercased()
        if l.contains("arrive") || l.contains("destination") { return "flag.checkered" }
        if l.contains("u-turn") || l.contains("uturn") { return "arrow.uturn.left" }
        if l.contains("left") { return "arrow.turn.up.left" }
        if l.contains("right") { return "arrow.turn.up.right" }
        if l.contains("merge") { return "arrow.merge" }
        if l.contains("roundabout") || l.contains("rotary") { return "arrow.triangle.turn.up.right.circle" }
        return "arrow.up"
    }

    private var leaderboardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if vm.leaderboardRows.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.surfaceContainerHigh.opacity(0.5))
                                .frame(width: 140, height: 56)
                                .redacted(reason: .placeholder)
                        }
                    } else {
                        ForEach(vm.leaderboardRows) { row in
                            LiveLeaderboardCard(row: row, isSelected: selectedRiderId == row.id)
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedRiderId) { _, id in
                if let id {
                    withAnimation(.spring(response: 0.4)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                regroupButton
                endRideButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .background(
            LinearGradient(
                colors: [.clear, Color.surfaceDim.opacity(0.65), Color.surfaceDim.opacity(0.97)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var regroupButton: some View {
        Button(action: { showRegroup = true }) {
            VStack(spacing: 5) {
                Image(systemName: "person.3.fill").font(.system(size: 19))
                Text("REGROUP")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
            }
            .foregroundColor(Color.onSurface)
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(Color.surfaceContainerHigh.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        }
    }

    private var endRideButton: some View {
        Button(action: {
            if vm.amILeader {
                Task { await vm.endRide() }
            } else {
                dismiss()
            }
        }) {
            VStack(spacing: 5) {
                if vm.isEnding {
                    ProgressView().tint(Color.errorColor).scaleEffect(0.8)
                } else {
                    Image(systemName: "stop.fill").font(.system(size: 19))
                }
                Text(vm.amILeader ? "END RIDE" : "LEAVE RIDE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
            }
            .foregroundColor(Color.errorColor)
            .frame(maxWidth: .infinity).frame(height: 72)
            .background(Color.errorContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.errorColor.opacity(0.35), lineWidth: 1))
        }
        .disabled(vm.isEnding)
    }

    // MARK: - Right Stat Pills

    private var rightStatPills: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 9) {
                    NavStatPill(
                        label: "SPEED",
                        value: vm.mySpeedKmh > 0 ? String(format: "%.0f", vm.mySpeedKmh) : "--",
                        unit: "KM/H"
                    )
                    NavStatPill(label: "ETA", value: vm.etaString, unit: nil)
                    NavStatPill(
                        label: "DIST",
                        value: vm.myDistanceToGoalKm > 0 ? String(format: "%.1f", vm.myDistanceToGoalKm) : "--",
                        unit: "KM"
                    )
                }
                .padding(.trailing, 14)
            }
            Spacer()
        }
        .padding(.top, 180)
        .padding(.bottom, 220)
    }
}

// MARK: - Live Rider Pin

struct LiveRiderPin: View {
    let rider: LiveRider
    let isSelected: Bool

    private var size: CGFloat { isSelected ? 52 : 42 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(rider.isMe ? Color.primaryFixed.opacity(0.15) : Color.surfaceContainerHigh)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(
                        isSelected ? Color.primaryFixed : (rider.isMe ? Color.primaryFixed : Color.outlineVariant.opacity(0.6)),
                        lineWidth: isSelected || rider.isMe ? 3 : 2
                    ))
                    .shadow(color: Color.primaryFixed.opacity(isSelected ? 0.6 : 0.2), radius: isSelected ? 14 : 5)

                if let url = rider.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Circle().fill(Color.surfaceVariant) }
                        .frame(width: size - 8, height: size - 8)
                        .clipShape(Circle())
                } else {
                    Text(String(rider.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundColor(rider.isMe ? Color.primaryFixed : Color.onSurface)
                }

                Text("\(rider.rank)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(rider.rank == 1 ? Color.onPrimaryFixed : Color.onSurface)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(rider.rank == 1 ? Color.primaryFixed : Color.surfaceContainerHighest)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 5, y: 5)
                    .frame(width: size, height: size)
            }

            Triangle()
                .fill(isSelected ? Color.primaryFixed : (rider.isMe ? Color.primaryFixed : Color.outlineVariant.opacity(0.6)))
                .frame(width: 10, height: 6)
                .offset(y: -1)

            if isSelected {
                Text(rider.name.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(Color.onSurface)
                    .tracking(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.surfaceContainerHigh.opacity(0.92))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Live Leaderboard Card

struct LiveLeaderboardCard: View {
    let row: NavLeaderboardRow
    var isSelected: Bool = false

    private var isHighlighted: Bool { row.rank == 1 || isSelected || row.isMe }
    private var firstName: String { row.name.components(separatedBy: " ").first ?? row.name }
    private var lastName: String {
        let parts = row.name.components(separatedBy: " ")
        return parts.dropFirst().joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 7) {
            Text("\(row.rank)")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurfaceVariant)
                .frame(width: 18)

            Group {
                if let url = row.avatarUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { Circle().fill(Color.surfaceVariant) }
                } else {
                    Circle().fill(Color.surfaceVariant)
                        .overlay(
                            Text(String(row.name.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isHighlighted ? Color.primaryFixed : Color.onSurface)
                        )
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
            .overlay(Circle().stroke(
                isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.4),
                lineWidth: isHighlighted ? 2 : 1
            ))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(firstName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.onSurface)
                        .lineLimit(1)
                    if row.isMe {
                        Text("YOU")
                            .font(.system(size: 6, weight: .black, design: .monospaced))
                            .foregroundColor(Color.onPrimaryFixed)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Color.primaryFixed).clipShape(Capsule())
                    }
                }
                if !lastName.isEmpty {
                    Text(lastName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Color.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isHighlighted ? Color.primaryFixed.opacity(0.12) : Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
            isHighlighted ? Color.primaryFixed : Color.outlineVariant.opacity(0.3),
            lineWidth: isHighlighted ? 1.5 : 1
        ))
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Destination Pin

// MARK: - Nav User Arrow

struct NavUserArrow: View {
    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.25))
                .frame(width: 48, height: 48)
            // Arrow body
            ZStack {
                Circle()
                    .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.3), radius: 4)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: -1)
            }
        }
    }
}

// MARK: - Waypoint Pin

struct WaypointPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.surfaceContainerHighest)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.tertiaryFixed, lineWidth: 2))
                    .shadow(color: Color.tertiaryFixed.opacity(0.4), radius: 6)
                Image(systemName: "mappin")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.tertiaryFixed)
            }
            Triangle().fill(Color.tertiaryFixed).frame(width: 8, height: 5).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Destination Pin

struct DestinationPin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(Color.primaryFixed).frame(width: 44, height: 44)
                    .shadow(color: Color.primaryFixed.opacity(0.7), radius: 12)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.onPrimaryFixed)
            }
            Triangle().fill(Color.primaryFixed).frame(width: 10, height: 6).offset(y: -1)
            Text(name.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .tracking(0.5)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.surfaceContainerHigh.opacity(0.92))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Start Pin

struct StartPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceContainerHighest)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.primaryFixed, lineWidth: 2))
                .shadow(color: Color.primaryFixed.opacity(0.3), radius: 8)
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.primaryFixed)
        }
    }
}

// MARK: - Nav Stat Pill

struct NavStatPill: View {
    let label: String
    let value: String
    let unit: String?
    var accentColor: Color? = nil

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.onSurfaceVariant).tracking(1)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(accentColor ?? Color.onSurface)
            if let unit {
                Text(unit).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Color.onSurfaceVariant)
            } else {
                Text(" ").font(.system(size: 8, weight: .medium, design: .monospaced))
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.surfaceContainerHigh.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    NavigationStack {
        RideNavigationView(rideId: "preview")
            .environmentObject(AppState())
            .environment(Clerk.shared)
    }
}
