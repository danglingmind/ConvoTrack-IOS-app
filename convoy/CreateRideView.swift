import SwiftUI
import MapKit

// MARK: - Route Stop Model

private struct RouteStop: Identifiable {
    let id = UUID()
    var text: String = ""
    var mapItem: MKMapItem? = nil
}

// MARK: - Stop Search Field

private struct StopSearchField: View {
    let label: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    @Binding var mapItem: MKMapItem?
    var onSelect: (() -> Void)? = nil

    @State private var results: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(2)
                .padding(.bottom, 8)

            ZStack(alignment: .leading) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(mapItem != nil ? Color.primaryFixed : Color.outline.opacity(0.5))
                    .padding(.leading, 16)

                TextField(placeholder, text: $text)
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)
                    .padding(.leading, 48)
                    .padding(.trailing, mapItem != nil ? 48 : 16)
                    .frame(height: 56)
                    .tint(Color.primaryFixed)

                if mapItem != nil {
                    HStack {
                        Spacer()
                        Button(action: { text = ""; mapItem = nil; results = [] }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color.onSurfaceVariant.opacity(0.7))
                                .font(.system(size: 18))
                        }
                        .padding(.trailing, 16)
                    }
                }
            }
            .background(Color.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(mapItem != nil ? Color.primaryFixed.opacity(0.5) : Color.outline.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: text) { _, newValue in
                // If user edits away from the confirmed name, clear selection so search reopens
                if let item = mapItem, newValue != (item.name ?? "") {
                    mapItem = nil
                }
                guard mapItem == nil else { results = []; return }

                searchTask?.cancel()
                guard newValue.count >= 2 else { results = []; return }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await performSearch(newValue)
                }
            }

            if !results.isEmpty && mapItem == nil {
                dropdownResults
            }
        }
    }

    private var dropdownResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.prefix(4).enumerated()), id: \.offset) { index, item in
                Button(action: {
                    text = item.name ?? ""
                    mapItem = item
                    results = []
                    onSelect?()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(Color.primaryFixed)
                            .font(.system(size: 16))
                        Text(item.name ?? "")
                            .font(.bodyMd).foregroundColor(Color.onSurface)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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

    @MainActor
    private func performSearch(_ query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
        } catch {
            results = []
        }
    }
}

// MARK: - Create Ride View

struct CreateRideView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var rideTitle = ""
    @State private var maxRiders = 10

    // Route stops — start + optional middle waypoints + destination
    @State private var startStop = RouteStop()
    @State private var middleStops: [RouteStop] = []
    @State private var endStop = RouteStop()

    // Computed route
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeDistance: Double = 0
    @State private var routeDuration: TimeInterval = 0
    @State private var mapPosition: MapCameraPosition = .automatic

    // API state
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false

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
            && startStop.mapItem != nil
            && endStop.mapItem != nil
            && !isCreating
    }

    // All confirmed stops in order for route calc and annotations
    private var confirmedStops: [MKMapItem] {
        var stops: [MKMapItem] = []
        if let s = startStop.mapItem { stops.append(s) }
        stops += middleStops.compactMap { $0.mapItem }
        if let e = endStop.mapItem { stops.append(e) }
        return stops
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.surfaceDim.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Color.clear.frame(height: 8)

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
                        routeStopsSection

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
                                    Image(systemName: "sportscourt.fill").font(.system(size: 20))
                                }
                            }
                            .modifier(LimePrimaryButton())
                        }
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.5)

                        Text("READY FOR DEPARTURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.onSurfaceVariant.opacity(0.4))
                            .tracking(8)

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                }
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
        }
    }

    // MARK: - Route Stops Section

    private var routeStopsSection: some View {
        VStack(spacing: 0) {
            // Start
            HStack(alignment: .top, spacing: 12) {
                stopDot(color: Color.tertiaryFixed, isFirst: true)
                StopSearchField(
                    label: "START LOCATION",
                    placeholder: "Search start point...",
                    icon: "location.fill",
                    text: $startStop.text,
                    mapItem: $startStop.mapItem,
                    onSelect: { Task { await recalculateRoute() } }
                )
            }

            // Middle waypoints
            ForEach($middleStops) { $stop in
                HStack(alignment: .top, spacing: 12) {
                    stopDot(color: Color.primaryFixed.opacity(0.6), isFirst: false)
                    HStack(alignment: .top, spacing: 8) {
                        StopSearchField(
                            label: "VIA",
                            placeholder: "Search stop...",
                            icon: "mappin",
                            text: $stop.text,
                            mapItem: $stop.mapItem,
                            onSelect: { Task { await recalculateRoute() } }
                        )
                        Button(action: {
                            middleStops.removeAll { $0.id == stop.id }
                            Task { await recalculateRoute() }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color.errorColor)
                                .padding(.top, 34)
                        }
                    }
                }
            }

            // Add stop button
            HStack(spacing: 12) {
                Rectangle().fill(Color.outline.opacity(0.2)).frame(width: 2).padding(.leading, 7)
                Button(action: { middleStops.append(RouteStop()) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(Color.primaryFixed)
                        Text("ADD STOP")
                            .font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
                    }
                }
                .padding(.vertical, 8)
            }

            // End destination
            HStack(alignment: .top, spacing: 12) {
                stopDot(color: Color.primaryFixed, isFirst: false)
                StopSearchField(
                    label: "DESTINATION",
                    placeholder: "Search destination...",
                    icon: "flag.checkered",
                    text: $endStop.text,
                    mapItem: $endStop.mapItem,
                    onSelect: { Task { await recalculateRoute() } }
                )
            }
        }
    }

    private func stopDot(color: Color, isFirst: Bool) -> some View {
        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(Color.outline.opacity(0.2))
                    .frame(width: 2)
                    .frame(height: 20)
            }
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
                .padding(.top, isFirst ? 34 : 0)
        }
    }

    // MARK: - Route Map Section

    private var routeMapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            routeMapHeader
            routeMapCanvas
            HStack(spacing: 12) {
                RouteStatCard(icon: "timer", label: "EST. TIME", value: durationText)
                RouteStatCard(icon: "arrow.triangle.turn.up.right.diamond", label: "DISTANCE", value: distanceText)
            }
        }
    }

    private var routeMapHeader: some View {
        HStack {
            Text("ROUTE PREVIEW")
                .font(.labelCaps).foregroundColor(Color.onSurfaceVariant).tracking(2)
            Spacer()
            Text(distanceText)
                .font(.labelCaps).foregroundColor(Color.primaryFixed).tracking(2)
        }
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
        Map(position: $mapPosition) {
            if !routeCoordinates.isEmpty {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(confirmedStops.enumerated()), id: \.offset) { index, item in
                let isEnd = index == confirmedStops.count - 1
                let dotColor: Color = isEnd ? .primaryFixed : (index == 0 ? .tertiaryFixed : Color.primaryFixed.opacity(0.6))
                let dotSize: CGFloat = isEnd ? 16 : 12
                let coord = item.location.coordinate
                Annotation("", coordinate: coord, anchor: .center) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(Circle().stroke(Color.surfaceDim, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
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
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.primaryContainer.opacity(0.2)).frame(width: 44, height: 44)
                Image(systemName: "person.3.fill").font(.system(size: 18)).foregroundColor(Color.primaryFixed)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Max Riders").font(.bodyLg).foregroundColor(Color.onSurface)
                Text("Maximum group size").font(.system(size: 12)).foregroundColor(Color.onSurfaceVariant)
            }
            Spacer()
            HStack(spacing: 16) {
                Button(action: { if maxRiders > 2 { maxRiders -= 1 } }) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 24)).foregroundColor(Color.primaryFixed)
                }
                Text("\(maxRiders)").font(.headlineMd).foregroundColor(Color.onSurface).frame(minWidth: 28)
                Button(action: { if maxRiders < 50 { maxRiders += 1 } }) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundColor(Color.primaryFixed)
                }
            }
        }
        .padding(16)
        .background(Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outline.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Route Calculation

    @MainActor
    private func recalculateRoute() async {
        let stops = confirmedStops
        guard stops.count >= 2 else {
            routeCoordinates = []
            routeDistance = 0
            routeDuration = 0
            if let first = stops.first {
                mapPosition = .region(MKCoordinateRegion(
                    center: first.location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                ))
            }
            return
        }

        var allCoords: [CLLocationCoordinate2D] = []
        var totalDist: Double = 0
        var totalTime: TimeInterval = 0

        for i in 0..<stops.count - 1 {
            let req = MKDirections.Request()
            req.source = stops[i]
            req.destination = stops[i + 1]
            req.transportType = .automobile
            do {
                let resp = try await MKDirections(request: req).calculate()
                guard let segment = resp.routes.first else { continue }
                let coords = segment.polyline.coordinates
                // Avoid duplicate junction point between segments
                allCoords += (i == 0) ? coords : Array(coords.dropFirst())
                totalDist += segment.distance
                totalTime += segment.expectedTravelTime
            } catch { continue }
        }

        routeCoordinates = allCoords
        routeDistance = totalDist
        routeDuration = totalTime

        if !allCoords.isEmpty {
            let poly = MKPolyline(coordinates: allCoords, count: allCoords.count)
            let rect = poly.boundingMapRect
            let padX = rect.width * 0.15
            let padY = rect.height * 0.15
            mapPosition = .rect(rect.insetBy(dx: -padX, dy: -padY))
        }
    }

    // MARK: - Create Ride

    @MainActor
    private func createRide() async {
        guard let start = startStop.mapItem, let dest = endStop.mapItem else { return }
        isCreating = true
        defer { isCreating = false }

        let destCoord = dest.location.coordinate
        let encodedPolyline = encodePolyline(routeCoordinates)

        // Build ordered waypoints: START → WAYPOINT* → DESTINATION
        var waypoints: [CreateWaypoint] = []
        let startCoord = start.location.coordinate
        waypoints.append(CreateWaypoint(
            order: 0,
            name: start.name ?? startStop.text,
            type: "START",
            lat: startCoord.latitude,
            lng: startCoord.longitude
        ))
        for stop in middleStops {
            guard let item = stop.mapItem else { continue }
            let c = item.location.coordinate
            waypoints.append(CreateWaypoint(
                order: waypoints.count,
                name: item.name ?? stop.text,
                type: "WAYPOINT",
                lat: c.latitude,
                lng: c.longitude
            ))
        }
        waypoints.append(CreateWaypoint(
            order: waypoints.count,
            name: dest.name ?? endStop.text,
            type: "DESTINATION",
            lat: destCoord.latitude,
            lng: destCoord.longitude
        ))

        let body = CreateRideRequest(
            title: rideTitle.trimmingCharacters(in: .whitespaces),
            destinationName: dest.name ?? endStop.text,
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

// MARK: - Google Polyline Encoding

private func encodePolyline(_ coordinates: [CLLocationCoordinate2D]) -> String {
    var result = ""
    var prevLat = 0
    var prevLng = 0
    for coord in coordinates {
        let lat = Int(round(coord.latitude * 1e5))
        let lng = Int(round(coord.longitude * 1e5))
        result += encodePolylineValue(lat - prevLat)
        result += encodePolylineValue(lng - prevLng)
        prevLat = lat
        prevLng = lng
    }
    return result
}

private func encodePolylineValue(_ value: Int) -> String {
    var v = value < 0 ? ~(value << 1) : value << 1
    var result = ""
    while v >= 0x20 {
        result.append(Character(UnicodeScalar((0x20 | (v & 0x1f)) + 63)!))
        v >>= 5
    }
    result.append(Character(UnicodeScalar(v + 63)!))
    return result
}

// MARK: - MKPolyline Extension

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
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
                Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
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
