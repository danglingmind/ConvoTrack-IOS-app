import SwiftUI
import MapKit
import ClerkKit
import Combine

// MARK: - ViewModel

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var participants: [RideParticipant] = []
    @Published var myStatus = "WAITING"   // optimistic local ready state
    @Published var isStarting = false
    @Published var socketConnected = false
    @Published var startError: String? = nil

    var rideId = ""
    var myUserId = ""
    var leaderId = ""

    var amILeader: Bool { !myUserId.isEmpty && myUserId == leaderId }

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

        // state_update carries LiveParticipant (GPS/progress) — consumed by RideNavigationView, not lobby
        socket.onStateUpdate = nil

        socket.onLobbyRoster = { [weak self] participants, leaderId in
            guard let self else { return }
            // Roster snapshot from server — use it to seed the list if REST failed
            if self.participants.isEmpty { self.participants = participants }
            if self.leaderId.isEmpty { self.leaderId = leaderId }
        }

        socket.onParticipantJoined = { [weak self] participant in
            guard let self else { return }
            if !self.participants.contains(where: { $0.userId == participant.userId }) {
                self.participants.append(participant)
            }
        }

        socket.onParticipantLeft = { [weak self] userId in
            self?.participants.removeAll { $0.userId == userId }
        }

        socket.onParticipantReady = { [weak self] userId in
            guard let self else { return }
            self.updateParticipantStatus(userId: userId, status: "READY")
            if userId == self.myUserId { self.myStatus = "READY" }
        }

        // Join the room after a brief moment for connection to establish
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            socket.joinRoom(rideId: rideId)
            self.socketConnected = true
        }
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
        SocketClient.shared.disconnect()
        socketConnected = false
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

// MARK: - RideLobbyView

struct RideLobbyView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = LobbyViewModel()

    @State private var showShareSheet = false
    @State private var showQRModal = false
    @State private var showRiderDetail = false
    @State private var showNavigation = false
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showStartError = false

    // MARK: - Derived

    private var rideTitle: String { appState.currentRide?.title ?? "Ride Lobby" }
    private var destinationName: String { appState.currentRide?.destinationName ?? "" }
    private var distanceKm: String {
        guard let d = appState.currentRide?.distanceMeters, d > 0 else { return "--" }
        return String(format: "%.0f", d / 1000)
    }
    private var inviteCode: String { appState.inviteCode ?? "" }

    private var myClerkName: String? {
        let parts = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? clerk.user?.username : name
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

            bottomBar
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(rideTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    vm.disconnect()
                    dismiss()
                }) {
                    Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                }
            }
        }
        .navigationDestination(isPresented: $showNavigation) {
            RideNavigationView(rideId: vm.rideId)
        }
        .background(
            ShareSheetPresenter(
                isPresented: $showShareSheet,
                items: inviteCode.isEmpty
                    ? ["Join my convoy ride!"]
                    : ["Join my convoy ride! Use code: \(inviteCode)"]
            )
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showRiderDetail) { RiderDetailDrawer() }
        .sheet(isPresented: $showQRModal) { QRCodeModal(inviteCode: inviteCode) }
        .alert("Couldn't Start Ride", isPresented: $showStartError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.startError ?? "An error occurred.")
        }
        .onChange(of: vm.startError) { _, err in
            if err != nil { showStartError = true }
        }
        .task { await loadRideAndConnect() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition, content: lobbyMapContent)
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, minHeight: 360)

            LinearGradient(
                colors: [Color.surfaceDim, Color.surfaceDim.opacity(0.55), .clear],
                startPoint: .bottom, endPoint: .top
            )
            .frame(height: 360)

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
        .frame(height: 360)
    }

    @MapContentBuilder
    private func lobbyMapContent() -> some MapContent {
        if !routeCoordinates.isEmpty {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        lobbyWaypointAnnotations
    }

    @MapContentBuilder
    private var lobbyWaypointAnnotations: some MapContent {
        let waypoints = appState.currentRide?.waypoints ?? []
        if let wp = waypoints.first(where: { $0.type == "START" }) {
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                LobbyStartPin()
            }
        }
        ForEach(waypoints.filter { $0.type == "WAYPOINT" }, id: \.order) { wp in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                WaypointPin(name: wp.name)
            }
        }
        if let wp = waypoints.first(where: { $0.type == "DESTINATION" }) {
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                DestinationPin(name: wp.name)
            }
        }
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
                        Button(action: { showRiderDetail = true }) {
                            ParticipantRiderRow(participant: participant, nameOverride: name, statusOverride: status)
                        }
                        .buttonStyle(PlainButtonStyle())
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

        if let token = try? await Clerk.shared.auth.getToken() {
            vm.setup(rideId: rideId, token: token)
        }
    }

    @MainActor
    private func calculateRoute(from waypoints: [Waypoint]) async {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard sorted.count >= 2 else { return }

        let items = sorted.map {
            MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)))
        }

        var allCoords: [CLLocationCoordinate2D] = []
        for i in 0..<items.count - 1 {
            let req = MKDirections.Request()
            req.source = items[i]; req.destination = items[i + 1]; req.transportType = .automobile
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                let coords = route.polyline.coordinates
                allCoords += (i == 0) ? coords : Array(coords.dropFirst())
            }
        }

        routeCoordinates = allCoords
        if !allCoords.isEmpty {
            let poly = MKPolyline(coordinates: allCoords, count: allCoords.count)
            let rect = poly.boundingMapRect
            mapPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
        } else if let first = sorted.first {
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ))
        }
    }
}

// MARK: - Participant Row

struct ParticipantRiderRow: View {
    let participant: RideParticipant
    var nameOverride: String? = nil
    var statusOverride: String? = nil

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
                    .fill(isReady ? Color.primaryFixed : Color.surfaceVariant)
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

            Text(displayStatus)
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
                Text("JOIN CONVOY").font(.headlineMd).foregroundColor(Color.primaryFixed).tracking(2)
                RoundedRectangle(cornerRadius: 16).fill(Color.white).frame(width: 256, height: 256)
                    .overlay(Image(systemName: "qrcode").font(.system(size: 200)).foregroundColor(Color.surfaceContainerLowest))
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
