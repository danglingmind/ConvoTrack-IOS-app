import SwiftUI
import CoreLocation
import CoreImage

struct RideSummaryView: View {
    var rideId: String?
    var rideTitle: String?
    var fallback: HistoryRide? = nil   // used when summary API has no record yet
    var isPostRide: Bool = false       // true only when navigating from active ride end

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var summary: RideSummary? = nil
    @State private var isLoading = true
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var mapWaypoints: [Waypoint] = []
    @State private var cameraCommand: MapCameraCommand? = nil
    @State private var destinationPhoto: DestinationPhoto? = nil

    @State private var isGeneratingShare = false
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet = false

    private var effectiveTitle: String {
        rideTitle ?? fallback?.title ?? "Ride Complete"
    }

    /// Terminal screen: no back button (DONE leaves), a sticky DONE, and the share action.
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                DSScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(topInset: proxy.safeAreaInsets.top)

                        VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                            if isLoading {
                                DSLoadingState()
                            } else if let s = summary {
                                metricsGrid(s)
                                awardsSection(s)
                            } else if let f = fallback {
                                fallbackMetricsGrid(f)
                            } else {
                                DSErrorState(title: "Summary unavailable") {
                                    isLoading = true
                                    Task { await loadSummary() }
                                }
                            }

                            DSSecondaryButton(
                                title: "Share summary",
                                systemImage: "square.and.arrow.up",
                                isLoading: isGeneratingShare
                            ) { Task { await generateAndShare() } }
                            .disabled(isGeneratingShare || isLoading)
                        }
                        .padding(.horizontal, DS.Space.screenInset)
                        .padding(.top, DS.Space.p5)
                        .padding(.bottom, DS.Space.sectionGap)
                    }
                    .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .dsStickyBottomAction {
            DSPrimaryButton(title: "Done") { finishAndDismiss() }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Ride Summary")
        .navigationBarTitleDisplayMode(.inline)
        .dsTransparentNavigationBar()
        .task { await loadSummary() }
        .task { await loadRoute() }
        .sheet(isPresented: $showShareSheet) {
            SummaryShareSheet(items: shareSheetItems)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    /// Destination photo (else the road photo) fading into the base, with the centred headline.
    private func hero(topInset: CGFloat) -> some View {
        VStack(spacing: DS.Space.p2) {
            Text("Ride complete").dsText(.eyebrow).foregroundStyle(DS.Accent.base)
            Text(effectiveTitle)
                .dsText(.heroTitle)
                .foregroundStyle(DS.Text.onPhoto)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .dsShadow(DS.Shadow.textOnPhoto)
                .accessibilityAddTraits(.isHeader)
            if let s = summary {
                Text("\(formatDistance(s.distanceMeters)) km · \(RideDuration.inline(s.durationSeconds))")
                    .dsText(.body)
                    .foregroundStyle(DS.Text.secondary)
                    .dsShadow(DS.Shadow.textOnPhoto)
            }
            if let photo = destinationPhoto, let attribution = photo.attribution {
                Text("Photo: \(attribution) · Google")
                    .dsText(.micro)
                    .foregroundStyle(DS.Text.onPhotoMuted)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.p3)
                    .frame(minHeight: 28)
                    .dsGlass(clear: true)
                    .padding(.top, DS.Space.p2)
            }
        }
        .padding(.horizontal, DS.Space.screenInset)
        .padding(.top, topInset + 24)
        .padding(.bottom, DS.Space.p5)
        .frame(maxWidth: .infinity, minHeight: topInset + 250, alignment: .bottom)
        .background { heroMedia }
    }

    private var heroMedia: some View {
        ZStack {
            if let photo = destinationPhoto {
                Color.clear
                    .overlay(Image(uiImage: photo.image).resizable().scaledToFill())
                    .clipped()
                DS.Gradient.photoFade
            } else {
                DSHeroPhoto(imageName: "hero_road_sunset", height: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
    }

    // MARK: - Metrics

    private var metricColumns: [GridItem] {
        // One column at accessibility sizes, otherwise 2×2.
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: DS.Space.p3), GridItem(.flexible())]
    }

    private func metricsGrid(_ s: RideSummary) -> some View {
        let duration = RideDuration.stat(s.durationSeconds)
        return LazyVGrid(columns: metricColumns, spacing: DS.Space.p3) {
            DSSummaryMetricCard(label: "Total distance", value: formatDistance(s.distanceMeters), unit: "KM", variant: .primary)
            DSSummaryMetricCard(label: "Duration", value: duration.value, unit: duration.unit)
            DSSummaryMetricCard(label: "Avg speed", value: s.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--", unit: "KM/H")
            DSSummaryMetricCard(
                label: "Max group split",
                value: String(format: "%.1f", s.maxGroupSplitMeters / 1000),
                unit: "KM",
                variant: s.maxGroupSplitMeters > 2000 ? .alert : .standard
            )
        }
    }

    private func fallbackMetricsGrid(_ f: HistoryRide) -> some View {
        let duration = RideDuration.stat(f.durationSeconds)
        return LazyVGrid(columns: metricColumns, spacing: DS.Space.p3) {
            DSSummaryMetricCard(label: "Total distance", value: String(format: "%.1f", f.distanceMeters / 1000), unit: "KM", variant: .primary)
            DSSummaryMetricCard(label: "Duration", value: duration.value, unit: duration.unit)
            DSSummaryMetricCard(label: "Avg speed", value: f.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--", unit: "KM/H")
            DSSummaryMetricCard(label: "Sync score", value: f.compactnessScore.map { "\(Int($0))%" } ?? "--")
        }
    }

    // MARK: - Awards

    private func awardsSection(_ s: RideSummary) -> some View {
        let ranked = s.participants.sorted { ($0.syncScore ?? 0) > ($1.syncScore ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            DSSectionHeading("Awards")
            VStack(spacing: DS.Space.p3) {
                ForEach(ranked, id: \.userId) { p in
                    DSAwardRow(
                        name: p.name,
                        id: p.userId,
                        awardTitle: displayTitle(p.rideTitle),
                        score: p.syncScore.map { "\($0)%" } ?? "--"
                    )
                }
            }
        }
        .padding(DS.Space.p4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurfaceCard(.card, radius: DS.Radius.lg)
    }

    // MARK: - Map Pins

    private var summaryMapPins: [MapPin] {
        var pins: [MapPin] = []
        if let wp = mapWaypoints.first(where: { $0.type == "START" }) {
            pins.append(MapPin(id: "start", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .lobbyStart))
        }
        for wp in mapWaypoints.filter({ $0.type == "WAYPOINT" }) {
            pins.append(MapPin(id: "wp_\(wp.order)", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .waypoint(name: wp.name)))
        }
        if let wp = mapWaypoints.first(where: { $0.type == "DESTINATION" }) {
            pins.append(MapPin(id: "dest", coordinate: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng), style: .destination(name: wp.name)))
        }
        return pins
    }

    // MARK: - Helpers

    private func loadSummary() async {
        guard let id = rideId else { isLoading = false; return }

        // Right after ending a ride the summary row can lag a moment behind the
        // navigation trigger (the `ride:state_update`/socket path can beat the
        // summary write becoming queryable). Retry briefly instead of giving up
        // on the first failure, which is what surfaced "Summary unavailable".
        let maxAttempts = isPostRide ? 6 : 1
        for attempt in 1...maxAttempts {
            if let result = try? await APIClient.shared.getRideSummary(id) {
                summary = result
                break
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
        isLoading = false
    }

    private func loadRoute() async {
        guard let id = rideId,
              let ride = try? await APIClient.shared.getRide(id) else { return }
        mapWaypoints = ride.waypoints
        // Destination photo for the hero (cached, shared with the lobby and Home).
        if !ride.destinationName.isEmpty {
            destinationPhoto = await GooglePlacePhotoService.shared.photo(
                destinationName: ride.destinationName,
                coordinate: CLLocationCoordinate2D(latitude: ride.destinationLat, longitude: ride.destinationLng)
            )
        }
        await calculateRoute(from: ride.waypoints, polyline: ride.routePolyline)
    }

    @MainActor
    private func calculateRoute(from waypoints: [Waypoint], polyline: String? = nil) async {
        // Prefer the leader-selected route geometry stored on the ride.
        if let stored = GoogleDirectionsService.decodedRoute(polyline) {
            routeCoordinates = stored
            cameraCommand = MapCameraCommand.fitRoute(stored, padding: 60)
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
            cameraCommand = MapCameraCommand.fitRoute(allCoords, padding: 60)
        } else if let first = sorted.first {
            cameraCommand = MapCameraCommand.focus(lat: first.lat, lng: first.lng, zoom: 11)
        }
    }

    // MARK: - Share

    @MainActor
    private func generateAndShare() async {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        let snapshot = await generateMapSnapshot(waypoints: mapWaypoints)
        let qrImg = generateQRCode(from: "https://convotrack.in")

        let distStr: String
        let durStr: String
        let durUnitStr: String
        let speedStr: String
        let count: Int
        let dateStr: String

        if let s = summary {
            distStr = formatDistance(s.distanceMeters)
            (durStr, durUnitStr) = RideDuration.stat(s.durationSeconds)
            speedStr = s.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--"
            count = s.participants.count
            dateStr = formatShareDate(s.createdAt)
        } else if let f = fallback {
            distStr = String(format: "%.1f", f.distanceMeters / 1000)
            (durStr, durUnitStr) = RideDuration.stat(f.durationSeconds)
            speedStr = f.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--"
            count = 0
            dateStr = formatShareDate(f.endedAt ?? f.createdAt ?? "")
        } else {
            distStr = "--"; durStr = "--"; durUnitStr = ""; speedStr = "--"; count = 0; dateStr = ""
        }

        let card = RideSummaryShareCard(
            rideTitle: effectiveTitle,
            snapshot: snapshot,
            waypoints: mapWaypoints,
            distanceKm: distStr,
            durationFormatted: durStr,
            durationUnit: durUnitStr,
            avgSpeedKmh: speedStr,
            riderCount: count,
            dateText: dateStr,
            qrImage: qrImg
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else { return }
        shareSheetItems = [image]
        showShareSheet = true
    }

    private func generateMapSnapshot(waypoints: [Waypoint]) async -> StaticMapSnapshot? {
        await GoogleStaticMapsService.snapshot(
            routeCoordinates: routeCoordinates,
            waypoints:        waypoints,
            size:             CGSize(width: 390, height: 640),
            scale:            2
        )
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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

    /// ISO8601 → "AUG 5, 2026" for the share card meta line. Empty if unparseable.
    private func formatShareDate(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? {
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: iso)
        }()
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }

}

// MARK: - Subviews

// MARK: - Share Sheet

private struct SummaryShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RideSummaryView(rideId: nil, rideTitle: "Preview Ride")
        .environmentObject(AppState())
}
