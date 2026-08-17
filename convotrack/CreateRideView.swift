import SwiftUI
import CoreLocation

// MARK: - Route Stop Model

private struct RouteStop: Identifiable {
    let id = UUID()
    var text: String = ""
    var place: PlaceResult? = nil
}

// MARK: - Stop Search Field

struct StopSearchField: View {
    let label: String
    let placeholder: String
    let icon: String
    let fieldID: String
    @Binding var text: String
    @Binding var place: PlaceResult?
    var onSelect: (() -> Void)? = nil
    var onResultsAppeared: ((String) -> Void)? = nil

    @State private var results: [PlaceResult] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !label.isEmpty {
                Text(label)
                    .font(.labelCaps)
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(2)
                    .padding(.bottom, 8)
            }

            if place != nil {
                confirmedRow
            } else {
                searchRow
                if !results.isEmpty {
                    dropdownResults
                        .id(fieldID + "_results")
                }
            }
        }
        .onChange(of: results) { _, newResults in
            if !newResults.isEmpty {
                onResultsAppeared?(fieldID + "_results")
            }
        }
    }

    private var confirmedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color.primaryFixed)
            Text(place?.name ?? "")
                .font(.bodyMd)
                .foregroundColor(Color.onSurface)
                .lineLimit(1)
            Spacer()
            Button(action: { text = ""; place = nil; results = [] }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                    .font(.system(size: 18))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryFixed.opacity(0.5), lineWidth: 1))
    }

    private var searchRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.outline.opacity(0.6))
                .font(.system(size: 16))
                .padding(.leading, 16)
            TextField(placeholder, text: $text)
                .font(.bodyMd)
                .foregroundColor(Color.onSurface)
                .tint(Color.primaryFixed)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .frame(height: 48)
                .onChange(of: text) { _, newValue in
                    searchTask?.cancel()
                    guard newValue.count >= 2 else { results = []; return }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        results = await GooglePlacesService.search(query: newValue, near: LocationService.shared.lastLocation)
                    }
                }
        }
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
    }

    private var dropdownResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.prefix(4).enumerated()), id: \.offset) { index, item in
                Button(action: {
                    text = item.name
                    place = item
                    results = []
                    onSelect?()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Color.primaryFixed)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurface)
                                .lineLimit(1)
                            if let addr = item.formattedAddress, !addr.isEmpty {
                                Text(addr)
                                    .font(.captionMd)
                                    .foregroundColor(Color.onSurfaceVariant)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let userLoc = LocationService.shared.lastLocation {
                            let dist = userLoc.distance(from: item.location)
                            Text(dist < 1000 ? "\(Int(dist)) m" : String(format: "%.1f km", dist / 1000))
                                .font(.dataMono)
                                .foregroundColor(Color.onSurfaceVariant)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if index < min(results.count, 4) - 1 {
                    Divider().background(Color.outline.opacity(0.2)).padding(.leading, 44)
                }
            }
        }
        .background(Color.surfaceContainerHighest)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
        .padding(.top, 4)
    }
}

// MARK: - Create Ride View

struct CreateRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.dismiss) private var dismiss

    @State private var rideTitle = ""
    @State private var maxRiders = 5
    @State private var showMembership = false

    private var riderCap: Int { membershipStore.isPremium ? 25 : 5 }

    // Route stops — start + optional middle waypoints + destination
    @State private var startStop = RouteStop()
    @State private var middleStops: [RouteStop] = []
    @State private var endStop = RouteStop()

    // Computed route
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeDistance: Double = 0
    @State private var routeDuration: TimeInterval = 0
    @State private var cameraCommand: MapCameraCommand? = nil

    // Alternative routes — only populated for a direct start→destination (no middle stops)
    @State private var routeAlternatives: [RouteOption] = []
    @State private var selectedRouteIndex = 0

    // API state
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false

    @State private var scrollTarget: String? = nil

    private var distanceText: String {
        guard routeDistance > 0 else { return "--" }
        return String(format: "%.1f KM", routeDistance / 1000)
    }

    private var durationText: String {
        guard routeDuration > 0 else { return "--" }
        let minutes = Int(routeDuration / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var canCreate: Bool {
        !rideTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && startStop.place != nil
            && endStop.place != nil
            && !isCreating
    }

    // All confirmed stops in order for route calc and annotations
    private var confirmedStops: [PlaceResult] {
        var stops: [PlaceResult] = []
        if let s = startStop.place { stops.append(s) }
        stops += middleStops.compactMap { $0.place }
        if let e = endStop.place { stops.append(e) }
        return stops
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.surfaceDim.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

                ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 24) {
                        // Ride title
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

                        // Route stops
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ROUTE")
                                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                            routeStopsSection
                        }

                        // Map + stats
                        routeMapSection

                        // Max riders
                        maxRidersRow

                        // CTA
                        Button(action: { Task { await createRide() } }) {
                            HStack(spacing: 12) {
                                if isCreating {
                                    ProgressView().tint(Color.onPrimaryFixed)
                                } else {
                                    Text("CREATE RIDE").font(.headlineMd).tracking(4)
                                    Image(systemName: "car.2.fill").font(.system(size: 20))
                                }
                            }
                            .modifier(LimePrimaryButton())
                        }
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.5)

                        Text("READY FOR DEPARTURE")
                            .font(.labelCaps)
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
                            .tracking(8)
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
            .navigationBarBackButtonHidden(true)
            .navigationTitle("CREATE RIDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color.primaryFixed)
                }
            }
            .alert("Failed to Create Ride", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .sheet(isPresented: $showMembership) {
                MembershipView().environmentObject(membershipStore)
            }
            .onAppear {
                // Clamp to plan limit in case default exceeds it (e.g. free tier = 5)
                maxRiders = min(maxRiders, riderCap)
            }
        }
    }

    // MARK: - Route Stops Section

    private var routeStopsSection: some View {
        VStack(spacing: 12) {
            // Start
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

            // Middle waypoints
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

            // Add stop — indented to align with field edges (dot 14pt + spacing 12pt = 26pt)
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

            // End destination
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

    // hasLabel: true  → label (~20pt) + 48pt field; center dot in the field row
    // hasLabel: false → 48pt field only; center dot in the field
    private func stopDot(color: Color, hasLabel: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
            .padding(.top, hasLabel ? 37 : 17)
    }

    // MARK: - Route Map Section

    private var routeMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            routeMapHeader
            routeMapCanvas
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

    private var routeMapHeader: some View {
        Text("ROUTE PREVIEW")
            .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
    }

    private var routeMapCanvas: some View {
        ZStack {
            routeMap
            if confirmedStops.count < 2 {
                routeMapPlaceholder
            }
        }
        .frame(maxWidth: .infinity).frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))
    }

    private var routeMap: some View {
        let stopPins: [MapPin] = confirmedStops.enumerated().map { index, stop in
            let isEnd   = index == confirmedStops.count - 1
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

    private var routeMapPlaceholder: some View {
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

    // MARK: - Max Riders Row

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
                        Text("Pro unlocks bigger packs")
                            .font(.labelCaps)
                            .tracking(0.5)
                        Spacer()
                        Text("UPGRADE →")
                            .font(.labelCaps)
                            .tracking(1)
                    }
                    .foregroundColor(Color.primaryFixed)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
    private func recalculateRoute() async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeAlternatives  = []
            selectedRouteIndex = 0
            routeCoordinates   = []
            routeDistance      = 0
            routeDuration      = 0
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
                    selectRoute(0, fitCamera: true)
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

    // MARK: - Create Ride

    @MainActor
    private func createRide() async {
        guard let start = startStop.place, let dest = endStop.place else { return }
        isCreating = true
        defer { isCreating = false }

        let destCoord       = dest.coordinate
        let encodedPolyline = GoogleDirectionsService.encodePolyline(routeCoordinates)

        // Build ordered waypoints: START → WAYPOINT* → DESTINATION
        var waypoints: [CreateWaypoint] = []
        let startCoord = start.coordinate
        waypoints.append(CreateWaypoint(
            order: 0,
            name: start.name,
            type: "START",
            lat: startCoord.latitude,
            lng: startCoord.longitude
        ))
        for stop in middleStops {
            guard let place = stop.place else { continue }
            let c = place.coordinate
            waypoints.append(CreateWaypoint(
                order: waypoints.count,
                name: place.name,
                type: "WAYPOINT",
                lat: c.latitude,
                lng: c.longitude
            ))
        }
        waypoints.append(CreateWaypoint(
            order: waypoints.count,
            name: dest.name,
            type: "DESTINATION",
            lat: destCoord.latitude,
            lng: destCoord.longitude
        ))

        let body = CreateRideRequest(
            title: rideTitle.trimmingCharacters(in: .whitespaces),
            destinationName: dest.name,
            destinationLat: destCoord.latitude,
            destinationLng: destCoord.longitude,
            distanceMeters: routeDistance,
            estimatedDurationSeconds: Int(routeDuration),
            maxAllowedParticipants: maxRiders,
            routePolyline: encodedPolyline,
            waypoints: waypoints
        )

        do {
            let response = try await APIClient.shared.createRide(body)
            appState.currentRideId = response.rideId
            appState.inviteCode = response.inviteCode
            appState.currentRide = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Subviews

struct FieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var iconLeading: Bool = false
    var iconColor: Color = Color.outline.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
            ZStack(alignment: iconLeading ? .leading : .trailing) {
                TextField(placeholder, text: $text)
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)
                    .padding(.horizontal, iconLeading ? 48 : 16)
                    .padding(.trailing, iconLeading ? 16 : 48)
                    .frame(height: 56)
                    .background(Color.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.3), lineWidth: 1))
                    .tint(Color.primaryFixed)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .padding(iconLeading ? .leading : .trailing, 16)
            }
        }
    }
}

struct RouteStatCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(Color.primaryFixed)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
                Text(value).font(.headlineMd).foregroundColor(Color.onSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outline.opacity(0.1), lineWidth: 1))
    }
}

#Preview {
    CreateRideView()
        .environmentObject(AppState())
}
