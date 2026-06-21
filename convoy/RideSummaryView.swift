import SwiftUI
import MapKit
import CoreImage

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

    @State private var isGeneratingShare = false
    @State private var shareSheetItems: [Any] = []
    @State private var showShareSheet = false

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
        .sheet(isPresented: $showShareSheet) {
            SummaryShareSheet(items: shareSheetItems)
        }
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
            Button(action: { Task { await generateAndShare() } }) {
                HStack(spacing: 8) {
                    if isGeneratingShare {
                        ProgressView()
                            .tint(Color.onPrimaryContainer)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isGeneratingShare ? "GENERATING..." : "SHARE SUMMARY")
                        .font(.bodyLg).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.primaryContainer)
                .foregroundColor(Color.onPrimaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isGeneratingShare || isLoading)
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

    // MARK: - Share

    @MainActor
    private func generateAndShare() async {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        let mapImg = await generateMapSnapshot(waypoints: mapWaypoints)
        let qrImg = generateQRCode(from: "https://convoy.app")

        let distStr: String
        let durStr: String
        let durUnitStr: String
        let speedStr: String
        let count: Int

        if let s = summary {
            distStr = formatDistance(s.distanceMeters)
            durStr = formatDuration(s.durationSeconds)
            durUnitStr = durationUnit(s.durationSeconds)
            speedStr = s.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--"
            count = s.participants.count
        } else if let f = fallback {
            distStr = String(format: "%.1f", f.distanceMeters / 1000)
            durStr = f.durationSeconds.map { formatDuration($0) } ?? "--"
            durUnitStr = f.durationSeconds.map { durationUnit($0) } ?? ""
            speedStr = f.avgSpeedKmh.map { String(format: "%.0f", $0) } ?? "--"
            count = 0
        } else {
            distStr = "--"; durStr = "--"; durUnitStr = ""; speedStr = "--"; count = 0
        }

        let card = RideSummaryShareCard(
            rideTitle: effectiveTitle,
            mapImage: mapImg,
            distanceKm: distStr,
            durationFormatted: durStr,
            durationUnit: durUnitStr,
            avgSpeedKmh: speedStr,
            riderCount: count,
            qrImage: qrImg
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else { return }
        shareSheetItems = [image]
        showShareSheet = true
    }

    private func generateMapSnapshot(waypoints: [Waypoint]) async -> UIImage? {
        guard !routeCoordinates.isEmpty else { return nil }
        let coords = routeCoordinates
        let wps = waypoints.sorted { $0.order < $1.order }

        let poly = MKPolyline(coordinates: coords, count: coords.count)
        let rect = poly.boundingMapRect

        // Asymmetric padding: push route toward top so it clears the text overlay at bottom.
        // In MKMapRect Y increases southward, so adding more to height = more space south.
        let expandX = rect.width * 0.28
        let expandTop = rect.height * 0.12
        let expandBottom = rect.height * 0.72
        let paddedRect = MKMapRect(
            x: rect.minX - expandX,
            y: rect.minY - expandTop,
            width: rect.width + expandX * 2,
            height: rect.height + expandTop + expandBottom
        )

        // 2× logical size for a sharp result when the image fills 390×700 pt at @2x rendering
        let s: CGFloat = 2
        let options = MKMapSnapshotter.Options()
        options.mapRect = paddedRect
        options.size = CGSize(width: 390 * s, height: 700 * s)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)

        return await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in
                guard let snapshot = snapshot else {
                    continuation.resume(returning: nil)
                    return
                }

                let imgSize = snapshot.image.size
                let rendered = UIGraphicsImageRenderer(size: imgSize).image { _ in
                    snapshot.image.draw(at: .zero)
                    guard let ctx = UIGraphicsGetCurrentContext() else { return }

                    let points = coords.map { snapshot.point(for: $0) }
                    guard let first = points.first else { return }

                    // -- Glow --
                    ctx.saveGState()
                    ctx.setStrokeColor(UIColor(red: 202/255, green: 243/255, blue: 0, alpha: 0.2).cgColor)
                    ctx.setLineWidth(22 * s)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.move(to: first)
                    points.dropFirst().forEach { ctx.addLine(to: $0) }
                    ctx.strokePath()
                    ctx.restoreGState()

                    // -- Lime route --
                    ctx.saveGState()
                    ctx.setStrokeColor(UIColor(red: 202/255, green: 243/255, blue: 0, alpha: 1).cgColor)
                    ctx.setLineWidth(5 * s)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.move(to: first)
                    points.dropFirst().forEach { ctx.addLine(to: $0) }
                    ctx.strokePath()
                    ctx.restoreGState()

                    // -- Waypoint pins + labels --
                    let imgW = imgSize.width
                    let shadow = NSShadow()
                    shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
                    shadow.shadowBlurRadius = 4 * s
                    shadow.shadowOffset = .zero

                    for wp in wps {
                        let coord = CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng)
                        let pt = snapshot.point(for: coord)

                        let dotColor: UIColor
                        let dotRadius: CGFloat

                        switch wp.type {
                        case "START":
                            dotColor = UIColor(red: 98/255, green: 1.0, blue: 150/255, alpha: 1)
                            dotRadius = 7 * s
                        case "DESTINATION":
                            dotColor = UIColor(red: 202/255, green: 243/255, blue: 0, alpha: 1)
                            dotRadius = 9 * s
                        default:
                            dotColor = UIColor.white.withAlphaComponent(0.9)
                            dotRadius = 5 * s
                        }

                        // Dot
                        ctx.saveGState()
                        ctx.setFillColor(dotColor.cgColor)
                        ctx.fillEllipse(in: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                                                   width: dotRadius * 2, height: dotRadius * 2))
                        ctx.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
                        ctx.setLineWidth(1.5 * s)
                        ctx.strokeEllipse(in: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                                                     width: dotRadius * 2, height: dotRadius * 2))
                        ctx.restoreGState()

                        guard !wp.name.isEmpty else { continue }

                        let font = UIFont.boldSystemFont(ofSize: 11 * s)
                        let labelAttrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: UIColor.white,
                            .shadow: shadow
                        ]
                        let text = wp.name as NSString
                        let textSize = text.size(withAttributes: labelAttrs)
                        let pad = 5 * s
                        let pillW = textSize.width + pad * 2
                        let pillH = textSize.height + pad

                        // Flip to left if near right edge
                        let labelX: CGFloat = (pt.x + dotRadius + 6 * s + pillW > imgW - 12 * s)
                            ? pt.x - dotRadius - 6 * s - pillW
                            : pt.x + dotRadius + 6 * s
                        let labelY = pt.y - pillH / 2

                        let pillRect = CGRect(x: labelX, y: labelY, width: pillW, height: pillH)
                        UIColor.black.withAlphaComponent(0.6).setFill()
                        UIBezierPath(roundedRect: pillRect, cornerRadius: 4 * s).fill()

                        text.draw(at: CGPoint(x: pillRect.minX + pad, y: pillRect.minY + pad / 2),
                                  withAttributes: labelAttrs)
                    }
                }
                continuation.resume(returning: rendered)
            }
        }
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
