import SwiftUI
import CoreLocation

struct EditRideView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var membershipStore: MembershipStore
    @Environment(\.dismiss) private var dismiss

    let ride: Ride

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

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showMembership = false

    @State private var scrollTarget: String? = nil

    init(ride: Ride) {
        self.ride = ride
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
        ZStack(alignment: .bottom) {
            Color.surfaceDim.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

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
        .navigationBarBackButtonHidden(true)
        .navigationTitle("EDIT RIDE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark").foregroundColor(Color.primaryFixed)
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
        .sheet(isPresented: $showMembership) {
            MembershipView().environmentObject(membershipStore)
        }
        .task { await recalculateRoute() }
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

            HStack(spacing: 12) {
                RouteStatCard(icon: "timer", label: "EST. TIME", value: durationText)
                RouteStatCard(icon: "arrow.triangle.turn.up.right.diamond", label: "DISTANCE", value: distanceText)
            }
        }
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
            isInteractive: false
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
                        Text("Pro unlocks up to 25 riders").font(.labelCaps).tracking(0.5)
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
    private func recalculateRoute() async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeCoordinates = []
            routeDistance    = 0
            routeDuration    = 0
            if let first = stops.first {
                cameraCommand = MapCameraCommand.focus(lat: first.coordinate.latitude, lng: first.coordinate.longitude, zoom: 13)
            }
            return
        }

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
            errorMessage = error.localizedDescription
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
