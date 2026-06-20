import SwiftUI
import MapKit

struct RideSummaryView: View {
    var rideId: String?
    var rideTitle: String?
    var fallback: HistoryRide? = nil   // used when summary API has no record yet
    var isPostRide: Bool = false       // true only when navigating from active ride end

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var summary: RideSummary? = nil
    @State private var isLoading = true
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var mapWaypoints: [Waypoint] = []
    @State private var mapPosition: MapCameraPosition = .automatic

    private var effectiveTitle: String {
        rideTitle ?? fallback?.title ?? "Ride Complete"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.surfaceDim.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection

                    VStack(spacing: 16) {
                        if isLoading {
                            ProgressView()
                                .tint(Color.primaryFixed)
                                .padding(.vertical, 40)
                        } else if let s = summary {
                            metricsGrid(s)
                            leaderboardSection(s)
                        } else if let f = fallback {
                            fallbackMetricsGrid(f)
                        } else {
                            Text("Summary unavailable")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurfaceVariant)
                                .padding(.vertical, 40)
                        }

                        actionButtons

                        Color.clear.frame(height: 100)
                    }
                    .padding(.top, 16)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("RIDE SUMMARY")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { finishAndDismiss() }) {
                    Image(systemName: "arrow.left").foregroundColor(Color.primaryFixed)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(Color.primaryFixed)
            }
        }
        .task { await loadSummary() }
        .task { await loadRoute() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if routeCoordinates.isEmpty {
                Color.surfaceContainerLow
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .overlay(
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 80))
                            .foregroundColor(Color.primaryFixed.opacity(0.15))
                    )
            } else {
                Map(position: $mapPosition, content: summaryMapContent)
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
            }

            LinearGradient(
                colors: [.clear, Color.surfaceDim.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 360)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12))
                    Text("RIDE COMPLETED")
                        .font(.labelCaps)
                        .tracking(2)
                }
                .foregroundColor(Color.tertiaryFixed)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.surfaceContainerHighest.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 20)
                .padding(.bottom, 4)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(effectiveTitle)
                            .font(.headlineLg)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                        if let s = summary {
                            Text("\(formatDistance(s.distanceMeters)) km · \(formatDuration(s.durationSeconds)) \(durationUnit(s.durationSeconds))")
                                .font(.bodyMd)
                                .foregroundColor(Color.onSurfaceVariant)
                        }
                    }
                    .padding(.horizontal, 20)
                    Spacer()
                }
            }
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 360)
    }

    // MARK: - Metrics

    private func metricsGrid(_ s: RideSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                label: "TOTAL DISTANCE",
                value: formatDistance(s.distanceMeters),
                unit: "KM",
                isPrimary: true
            )
            MetricCard(
                label: "DURATION",
                value: formatDuration(s.durationSeconds),
                unit: durationUnit(s.durationSeconds),
                isPrimary: false
            )
            MetricCard(
                label: "AVG SPEED",
                value: s.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--",
                unit: "KM/H",
                isPrimary: false
            )
            MetricCard(
                label: "MAX GROUP SPLIT",
                value: String(format: "%.1f", s.maxGroupSplitMeters / 1000),
                unit: "KM",
                isPrimary: false,
                isError: s.maxGroupSplitMeters > 2000
            )
        }
        .padding(.horizontal, 20)
    }

    private func fallbackMetricsGrid(_ f: HistoryRide) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                label: "TOTAL DISTANCE",
                value: String(format: "%.1f", f.distanceMeters / 1000),
                unit: "KM",
                isPrimary: true
            )
            MetricCard(
                label: "DURATION",
                value: f.durationSeconds.map { formatDuration($0) } ?? "--",
                unit: f.durationSeconds.map { durationUnit($0) } ?? "",
                isPrimary: false
            )
            MetricCard(
                label: "AVG SPEED",
                value: f.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--",
                unit: "KM/H",
                isPrimary: false
            )
            MetricCard(
                label: "SYNC SCORE",
                value: f.compactnessScore.map { "\(Int($0))%" } ?? "--",
                unit: "",
                isPrimary: false
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Leaderboard

    private func leaderboardSection(_ s: RideSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("FINAL ORDER")
                    .font(.labelCaps)
                    .foregroundColor(Color.primaryFixed)
                    .tracking(4)
                Spacer()
                Text("SYNC RANKING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.onSurfaceVariant)
                    .tracking(1)
            }

            let ranked = s.participants.sorted { ($0.syncScore ?? 0) > ($1.syncScore ?? 0) }
            VStack(spacing: 12) {
                ForEach(Array(ranked.enumerated()), id: \.element.userId) { index, p in
                    LeaderboardRow(
                        rank: String(format: "%02d", index + 1),
                        name: p.name,
                        role: roleLabel(p),
                        sync: p.syncScore.map { "\($0)%" } ?? "--",
                        isFirst: index == 0
                    )
                }
            }
        }
        .padding(16)
        .background(Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("SHARE SUMMARY").font(.bodyLg).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.primaryContainer)
                .foregroundColor(Color.onPrimaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button(action: { finishAndDismiss() }) {
                Text("DONE")
                    .font(.bodyLg)
                    .foregroundColor(Color.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.outlineVariant.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Map Content

    @MapContentBuilder
    private func summaryMapContent() -> some MapContent {
        MapPolyline(coordinates: routeCoordinates)
            .stroke(Color.primaryFixed, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        summaryWaypointAnnotations
    }

    @MapContentBuilder
    private var summaryWaypointAnnotations: some MapContent {
        if let wp = mapWaypoints.first(where: { $0.type == "START" }) {
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                LobbyStartPin()
            }
        }
        ForEach(mapWaypoints.filter { $0.type == "WAYPOINT" }, id: \.order) { wp in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                WaypointPin(name: wp.name)
            }
        }
        if let wp = mapWaypoints.first(where: { $0.type == "DESTINATION" }) {
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), anchor: .bottom) {
                DestinationPin(name: wp.name)
            }
        }
    }

    // MARK: - Helpers

    private func loadSummary() async {
        guard let id = rideId else { isLoading = false; return }
        summary = try? await APIClient.shared.getRideSummary(id)
        isLoading = false
    }

    private func loadRoute() async {
        guard let id = rideId,
              let ride = try? await APIClient.shared.getRide(id) else { return }
        mapWaypoints = ride.waypoints
        await calculateRoute(from: ride.waypoints)
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

    private func finishAndDismiss() {
        if isPostRide {
            appState.currentRideId = nil
            appState.inviteCode = nil
            appState.currentRide = nil
            appState.popToRoot = true
        } else {
            dismiss()
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.1f", meters / 1000)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 3600 {
            return "\(seconds / 60)"
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private func durationUnit(_ seconds: Int) -> String {
        seconds < 3600 ? "MIN" : "HRS"
    }

    private func roleLabel(_ p: SummaryParticipant) -> String {
        let title = displayTitle(p.rideTitle)
        let sync = p.syncScore.map { " • \($0)% SYNC" } ?? ""
        return title.isEmpty ? sync.trimmingCharacters(in: .init(charactersIn: " •")) : title + sync
    }
}

// MARK: - Subviews

struct MetricCard: View {
    let label: String
    let value: String
    let unit: String
    let isPrimary: Bool
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.labelCaps)
                .foregroundColor(Color.onSurfaceVariant)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.displayMetrics)
                    .foregroundColor(isError ? Color.errorColor : (isPrimary ? Color.primaryFixed : Color.onSurface))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.labelCaps).foregroundColor(Color.onSurfaceVariant.opacity(isError ? 0.7 : 1))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .leading)
        .padding(16)
        .background(Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.outlineVariant.opacity(0.3), lineWidth: 1))
        .shadow(color: isPrimary ? Color.primaryFixed.opacity(0.1) : .clear, radius: 8)
    }
}

struct LeaderboardRow: View {
    let rank: String
    let name: String
    let role: String
    let sync: String
    var isFirst: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Text(rank)
                .font(.system(size: 24, weight: .bold))
                .italic()
                .foregroundColor(isFirst ? Color.primaryFixed : Color.onSurfaceVariant)
                .frame(width: 32)

            Circle()
                .fill(Color.surfaceVariant)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isFirst ? Color.primaryFixed : Color.onSurfaceVariant)
                )
                .overlay(Circle().stroke(isFirst ? Color.primaryFixed : Color.outlineVariant, lineWidth: 1))
                .opacity(isFirst ? 1 : 0.8)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.bodyLg).foregroundColor(Color.onSurface)
                Text(role).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color.onSurfaceVariant).tracking(1)
            }

            Spacer()

            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.primaryFixed)
            }
        }
        .padding(12)
        .background(isFirst ? Color.surfaceContainerHigh : Color.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            HStack {
                Rectangle()
                    .fill(isFirst ? Color.primaryFixed : Color.outlineVariant.opacity(0.5))
                    .frame(width: 4)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }
}

#Preview {
    RideSummaryView(rideId: nil, rideTitle: "Preview Ride")
        .environmentObject(AppState())
}
