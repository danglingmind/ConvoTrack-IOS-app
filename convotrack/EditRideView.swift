import SwiftUI
import CoreLocation
import ClerkKit

struct EditRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(Clerk.self) private var clerk
    @Environment(\.dismiss) private var dismiss

    let ride: Ride

    /// Called after the ride is successfully deleted, so the presenting lobby can tear
    /// down its session and pop back instead of refreshing a now-nonexistent ride.
    var onDeleted: () -> Void = {}

    @State private var rideTitle: String
    @State private var maxRiders: Int

    private var riderCap: Int { membershipStore.isPremium ? 25 : 5 }

    @State private var startStop: RouteStop
    @State private var middleStops: [RouteStop]
    @State private var endStop: RouteStop

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeDistance: Double = 0
    @State private var routeDuration: TimeInterval = 0
    @State private var cameraCommand: MapCameraCommand? = nil

    // Alternative routes — only populated for a direct start→destination (no middle stops)
    @State private var routeAlternatives: [RouteOption] = []
    @State private var selectedRouteIndex = 0

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showMembership = false

    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false

    /// Only the ride's creator (leader) may delete it. Read reactively from Clerk so a
    /// still-loading identity resolves the moment it lands.
    private var isLeader: Bool {
        guard let uid = clerk.user?.id, !uid.isEmpty else { return false }
        return uid == ride.leaderId
    }

    @State private var scrollTarget: String? = nil

    init(ride: Ride, onDeleted: @escaping () -> Void = {}) {
        self.ride = ride
        self.onDeleted = onDeleted
        _rideTitle = State(initialValue: ride.title)
        _maxRiders = State(initialValue: ride.maxAllowedParticipants)

        let sorted = ride.waypoints.sorted { $0.order < $1.order }

        if let wp = sorted.first(where: { $0.type == "START" }) {
            let place = PlaceResult(id: "wp_start", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            _startStop = State(initialValue: RouteStop(text: wp.name, place: place))
        } else {
            _startStop = State(initialValue: RouteStop())
        }

        let midWaypoints = sorted.filter { $0.type == "WAYPOINT" }
        _middleStops = State(initialValue: midWaypoints.map { wp in
            let place = PlaceResult(id: "wp_\(wp.order)", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            return RouteStop(text: wp.name, place: place)
        })

        if let wp = sorted.first(where: { $0.type == "DESTINATION" }) {
            let place = PlaceResult(id: "wp_dest", name: wp.name,
                                    coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng),
                                    formattedAddress: nil)
            _endStop = State(initialValue: RouteStop(text: wp.name, place: place))
        } else {
            _endStop = State(initialValue: RouteStop())
        }
    }

    private var distanceText: String {
        guard routeDistance > 0 else { return "--" }
        return String(format: "%.1f KM", routeDistance / 1000)
    }

    private var durationText: String {
        guard routeDuration > 0 else { return "--" }
        let minutes = Int(routeDuration / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var canSave: Bool {
        !rideTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && startStop.place != nil
            && endStop.place != nil
            && routeDistance > 0
            && !isSaving
    }

    private var confirmedStops: [PlaceResult] {
        var stops: [PlaceResult] = []
        if let s = startStop.place { stops.append(s) }
        stops += middleStops.compactMap { $0.place }
        if let e = endStop.place { stops.append(e) }
        return stops
    }

    var body: some View {
        // The background is a `.background` on the ZStack, not a full-bleed child inside it. As a
        // child, its `.ignoresSafeArea()` consumed the safe area for its sibling ScrollView — and
        // the keyboard is reported through the safe area, so SwiftUI's keyboard avoidance had
        // nothing to shrink and the focused field could sit under the keyboard. This form has five
        // text fields (title plus every stop), so it was the worst affected screen.
        ZStack(alignment: .bottom) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RIDE TITLE")
                                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                            ZStack(alignment: .trailing) {
                                TextField("e.g., Midnight Canyon Run", text: $rideTitle)
                                    .font(.bodyLg)
                                    .foregroundColor(Color.onSurface)
                                    .padding(.horizontal, 16)
                                    .padding(.trailing, 48)
                                    .frame(height: 56)
                                    .background(Color.surfaceContainerHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
                                    .tint(Color.primaryFixed)
                                Image(systemName: "pencil")
                                    .font(.system(size: 18))
                                    .foregroundColor(Color.outline.opacity(0.5))
                                    .padding(.trailing, 16)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("ROUTE")
                                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                            routeStopsSection
                        }

                        routeMapSection

                        maxRidersRow

                        Button(action: { Task { await saveRide() } }) {
                            HStack(spacing: 12) {
                                if isSaving {
                                    ProgressView().tint(Color.onPrimaryFixed)
                                } else {
                                    Text("SAVE CHANGES").font(.headlineMd).tracking(4)
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                                }
                            }
                            .modifier(LimePrimaryButton())
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)

                        Text("READY FOR DEPARTURE")
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
                            .tracking(8)

                        deleteRideButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .bottom)
                        }
                        scrollTarget = nil
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(
            Color.surfaceDim
                .ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                }
        )
        .navigationBarBackButtonHidden(true)
        .navigationTitle("EDIT RIDE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    // Back arrow, not a close X: this is a pushed page now, same as CREATE RIDE.
                    Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color.primaryFixed)
            }
        }
        .alert("Failed to Save Ride", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .alert("Delete this ride?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Ride", role: .destructive) { Task { await deleteRide() } }
        } message: {
            Text("This permanently deletes the ride for everyone. This can't be undone.")
        }
        .alert("Failed to Delete Ride", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showMembership) {
            MembershipView().environmentObject(membershipStore)
        }
        .task {
            // Show the currently-saved route instantly, then load alternatives and
            // preselect the one matching it.
            if let stored = GoogleDirectionsService.decodedRoute(ride.routePolyline) {
                routeCoordinates = stored
                routeDistance    = ride.distanceMeters
                routeDuration    = TimeInterval(ride.estimatedDurationSeconds)
                cameraCommand    = MapCameraCommand.fitRoute(stored, padding: 40)
            }
            await recalculateRoute(preferStoredMatch: true)
        }
    }

    // MARK: - Route Stops

    private var routeStopsSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                stopDot(color: Color.tertiaryFixed, hasLabel: true)
                StopSearchField(
                    label: "START LOCATION",
                    placeholder: "Search start point...",
                    icon: "location.fill",
                    fieldID: "start",
                    text: $startStop.text,
                    place: $startStop.place,
                    onSelect: { Task { await recalculateRoute() } },
                    onResultsAppeared: { id in scrollTarget = id }
                )
            }

            ForEach($middleStops) { $stop in
                HStack(alignment: .top, spacing: 12) {
                    stopDot(color: Color.primaryFixed.opacity(0.6), hasLabel: false)
                    HStack(alignment: .top, spacing: 8) {
                        StopSearchField(
                            label: "",
                            placeholder: "Search stop...",
                            icon: "mappin",
                            fieldID: "stop_\(stop.id)",
                            text: $stop.text,
                            place: $stop.place,
                            onSelect: { Task { await recalculateRoute() } },
                            onResultsAppeared: { id in scrollTarget = id }
                        )
                        Button(action: {
                            middleStops.removeAll { $0.id == stop.id }
                            Task { await recalculateRoute() }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.errorColor)
                                .padding(.top, 13)
                        }
                    }
                }
            }

            Button(action: { middleStops.append(RouteStop()) }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(Color.primaryFixed)
                    Text("ADD STOP")
                        .font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                }
            }
            .padding(.leading, 26)
            .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 12) {
                stopDot(color: Color.primaryFixed, hasLabel: true)
                StopSearchField(
                    label: "DESTINATION",
                    placeholder: "Search destination...",
                    icon: "flag.checkered",
                    fieldID: "destination",
                    text: $endStop.text,
                    place: $endStop.place,
                    onSelect: { Task { await recalculateRoute() } },
                    onResultsAppeared: { id in scrollTarget = id }
                )
            }
        }
    }

    private func stopDot(color: Color, hasLabel: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
            .padding(.top, hasLabel ? 37 : 17)
    }

    // MARK: - Route Map

    private var routeMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE PREVIEW")
                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
            ZStack {
                routeMap
                if confirmedStops.count < 2 {
                    ZStack {
                        Color.surfaceContainerLow.opacity(0.92)
                        VStack(spacing: 8) {
                            Image(systemName: "map").font(.system(size: 28)).foregroundColor(Color.onSurfaceVariant)
                            Text("ADD START & DESTINATION")
                                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))

            routeSelectorChips

            HStack(spacing: 12) {
                RouteStatCard(icon: "timer", label: "EST. TIME", value: durationText)
                RouteStatCard(icon: "arrow.triangle.turn.up.right.diamond", label: "DISTANCE", value: distanceText)
            }
        }
    }

    // Horizontally scrollable route options — shown only for a direct start→destination
    // route with more than one alternative. Tapping a chip (or the dim map line) selects it.
    @ViewBuilder
    private var routeSelectorChips: some View {
        if routeAlternatives.count > 1 {
            let fastest = routeAlternatives.map(\.durationSeconds).min() ?? 0
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(routeAlternatives.enumerated()), id: \.element.id) { index, option in
                        let isSelected = index == selectedRouteIndex
                        let delta = Int((option.durationSeconds - fastest) / 60)
                        Button { selectRoute(index) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(delta == 0 ? "FASTEST" : "+\(delta) MIN")
                                    .font(.labelCaps).tracking(1)
                                    .foregroundColor(isSelected ? Color.onPrimaryFixed.opacity(0.7) : Color.tertiaryFixed)
                                Text(durationString(Int(option.durationSeconds / 60)))
                                    .font(.dataMono)
                                    .foregroundColor(isSelected ? Color.onPrimaryFixed : Color.onSurface)
                                Text(String(format: "%.1f KM", option.distanceMeters / 1000))
                                    .font(.labelCaps).tracking(1)
                                    .foregroundColor(isSelected ? Color.onPrimaryFixed.opacity(0.7) : Color.onSurfaceVariant)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(isSelected ? Color.primaryFixed : Color.surfaceContainerHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.clear : Color.outline.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func durationString(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var routeMap: some View {
        let stopPins: [MapPin] = confirmedStops.enumerated().map { index, stop in
            let isEnd  = index == confirmedStops.count - 1
            let color: UIColor = isEnd
                ? UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 1)
                : (index == 0 ? UIColor(red: 0.384, green: 1, blue: 0.588, alpha: 1)
                              : UIColor(red: 0.792, green: 0.953, blue: 0, alpha: 0.6))
            let size: CGFloat = isEnd ? 16 : 12
            return MapPin(id: "stop_\(index)", coordinate: stop.coordinate,
                          style: .simpleDot(color: color, size: size), anchorBottom: false)
        }
        return GoogleMapView(
            routeCoords:   routeCoordinates,
            pins:          stopPins,
            cameraCommand: cameraCommand,
            isInteractive: !routeAlternatives.isEmpty,   // enable taps to pick alternatives
            alternativeRoutes: routeAlternatives.map { $0.coordinates },
            selectedRouteIndex: selectedRouteIndex,
            onSelectRoute: { index in selectRoute(index) }
        )
    }

    // MARK: - Max Riders

    private var maxRidersRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.primaryContainer.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: "person.3.fill").font(.iconMd).foregroundColor(Color.primaryFixed)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max Riders").font(.bodyLg).foregroundColor(Color.onSurface)
                    Text("Maximum group size").font(.labelCaps).foregroundColor(Color.onSurfaceVariant)
                }
                Spacer()
                HStack(spacing: 16) {
                    Button(action: { if maxRiders > 2 { maxRiders -= 1 } }) {
                        Image(systemName: "minus.circle.fill").font(.iconLg).foregroundColor(Color.primaryFixed)
                    }
                    Text("\(maxRiders)").font(.headlineMd).foregroundColor(Color.onSurface).frame(minWidth: 28)
                    Button(action: {
                        if maxRiders < riderCap {
                            maxRiders += 1
                        } else if !membershipStore.isPremium {
                            showMembership = true
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.iconLg)
                            .foregroundColor(atRiderCap ? Color.primaryFixed.opacity(0.35) : Color.primaryFixed)
                    }
                }
            }
            .padding(16)
            .background(Color.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))

            if atRiderCap {
                Button { showMembership = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill").font(.iconXS)
                        Text("Pro unlocks bigger packs").font(.labelCaps).tracking(0.5)
                        Spacer()
                        Text("UPGRADE →").font(.labelCaps).tracking(1)
                    }
                    .foregroundColor(Color.primaryFixed)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.primaryFixed.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primaryFixed.opacity(0.25), lineWidth: 1))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: atRiderCap)
    }

    private var atRiderCap: Bool { maxRiders >= riderCap && !membershipStore.isPremium }

    // MARK: - Route Calculation

    @MainActor
    private func recalculateRoute(preferStoredMatch: Bool = false) async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeAlternatives  = []
            selectedRouteIndex = 0
            routeCoordinates = []
            routeDistance    = 0
            routeDuration    = 0
            if let first = stops.first {
                cameraCommand = MapCameraCommand.focus(lat: first.coordinate.latitude, lng: first.coordinate.longitude, zoom: 13)
            }
            return
        }

        // Direct start→destination: offer selectable alternatives.
        // (Google returns none once intermediate waypoints are present.)
        if stops.count == 2 {
            do {
                let options = try await GoogleDirectionsService.alternativeRoutes(from: stops[0].coordinate, to: stops[1].coordinate)
                if options.count > 1 {
                    routeAlternatives = options
                    // On initial load, keep the leader's saved route selected.
                    selectRoute(preferStoredMatch ? bestMatchIndex(options) : 0, fitCamera: true)
                    return
                }
            } catch { /* fall through to the single-route path below */ }
        }

        // Has middle stops, or only one/zero alternatives: single stitched route.
        routeAlternatives  = []
        selectedRouteIndex = 0

        var allCoords: [CLLocationCoordinate2D] = []
        var totalDist: Double = 0
        var totalTime: TimeInterval = 0

        for i in 0..<stops.count - 1 {
            do {
                let result = try await GoogleDirectionsService.route(from: stops[i].coordinate, to: stops[i+1].coordinate)
                allCoords += (i == 0) ? result.coordinates : Array(result.coordinates.dropFirst())
                totalDist += result.distanceMeters
                totalTime += result.durationSeconds
            } catch { continue }
        }

        routeCoordinates = allCoords
        routeDistance    = totalDist
        routeDuration    = totalTime

        if !allCoords.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 40)
        }
    }

    /// Applies the alternative at `index` as the active route. `fitCamera` is true only
    /// for the initial pick; manual selection keeps the camera steady (endpoints match).
    @MainActor
    private func selectRoute(_ index: Int, fitCamera: Bool = false) {
        guard routeAlternatives.indices.contains(index) else { return }
        selectedRouteIndex = index
        let option = routeAlternatives[index]
        routeCoordinates = option.coordinates
        routeDistance    = option.distanceMeters
        routeDuration    = option.durationSeconds
        if fitCamera, !option.coordinates.isEmpty {
            cameraCommand = MapCameraCommand.fitRoute(option.coordinates, padding: 40)
        }
    }

    /// Picks the alternative closest to the ride's saved distance, so re-opening edit
    /// keeps the leader's previously-selected route highlighted.
    private func bestMatchIndex(_ options: [RouteOption]) -> Int {
        let target = ride.distanceMeters
        guard target > 0 else { return 0 }
        var best = 0
        var bestDiff = Double.greatestFiniteMagnitude
        for (i, option) in options.enumerated() {
            let diff = abs(option.distanceMeters - target)
            if diff < bestDiff { bestDiff = diff; best = i }
        }
        return best
    }

    // MARK: - Delete

    // Full-width destructive action pinned to the end of the sheet. Shown only to the ride's
    // creator (leader); disabled while a save or delete is already in flight.
    @ViewBuilder
    private var deleteRideButton: some View {
        if isLeader {
            Button(action: { showDeleteConfirm = true }) {
                HStack(spacing: 12) {
                    if isDeleting {
                        ProgressView().tint(Color.errorColor)
                    } else {
                        Image(systemName: "trash").font(.system(size: 18, weight: .semibold))
                        Text("DELETE RIDE").font(.headlineMd).tracking(4)
                    }
                }
                .foregroundColor(Color.errorColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.errorColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.errorColor.opacity(0.4), lineWidth: 1))
            }
            .disabled(isDeleting || isSaving)
            .opacity(isSaving ? 0.5 : 1)
        }
    }

    @MainActor
    private func deleteRide() async {
        guard isLeader else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteRide(ride.id)
            onDeleted()
            dismiss()
        } catch {
            deleteErrorMessage = error.riderMessage
            showDeleteError = true
        }
    }

    // MARK: - Save

    @MainActor
    private func saveRide() async {
        guard let start = startStop.place, let dest = endStop.place else { return }
        isSaving = true
        defer { isSaving = false }

        let destCoord       = dest.coordinate
        let encodedPolyline = GoogleDirectionsService.encodePolyline(routeCoordinates)

        var waypoints: [CreateWaypoint] = []
        let startCoord = start.coordinate
        waypoints.append(CreateWaypoint(order: 0, name: start.name, type: "START",
                                        lat: startCoord.latitude, lng: startCoord.longitude))
        for stop in middleStops {
            guard let place = stop.place else { continue }
            let c = place.coordinate
            waypoints.append(CreateWaypoint(order: waypoints.count, name: place.name, type: "WAYPOINT",
                                            lat: c.latitude, lng: c.longitude))
        }
        waypoints.append(CreateWaypoint(order: waypoints.count, name: dest.name, type: "DESTINATION",
                                        lat: destCoord.latitude, lng: destCoord.longitude))

        let request = UpdateRideRequest(
            title:                    rideTitle.trimmingCharacters(in: .whitespaces),
            destinationName:          dest.name,
            destinationLat:           destCoord.latitude,
            destinationLng:           destCoord.longitude,
            distanceMeters:           routeDistance,
            estimatedDurationSeconds: Int(routeDuration),
            maxAllowedParticipants:   maxRiders,
            routePolyline:            encodedPolyline,
            waypoints:                waypoints
        )

        do {
            try await APIClient.shared.updateRide(ride.id, request)
            dismiss()
        } catch {
            errorMessage = error.riderMessage
            showError = true
        }
    }
}

// MARK: - RouteStop (local to EditRideView)

private struct RouteStop: Identifiable {
    let id = UUID()
    var text: String = ""
    var place: PlaceResult? = nil
}
