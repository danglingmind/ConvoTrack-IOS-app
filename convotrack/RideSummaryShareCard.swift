import SwiftUI
import CoreLocation

// Poster-style ride recap card (Ten Thousand "10K" layout, ConvoTrack theme):
// brand wordmark + hero distance up top, the route as a bold lime outline over a
// label-free near-black basemap, a single inline stat row, and a bottom meta block
// in bold tracked uppercase. The only place names on the card are ours — drawn as
// named markers projected onto the route.
struct RideSummaryShareCard: View {
    let rideTitle: String
    let snapshot: StaticMapSnapshot?
    let waypoints: [Waypoint]
    let distanceKm: String
    let durationFormatted: String
    let durationUnit: String
    let avgSpeedKmh: String
    let riderCount: Int
    let dateText: String
    let qrImage: UIImage?

    private let cardSize = CGSize(width: 390, height: 700)
    // Static Maps free-tier cap (640pt tall); the map is a top-anchored hero and the
    // dark tail below it sits under the meta block.
    private let mapSize = CGSize(width: 390, height: 640)

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "131313")
                .frame(width: cardSize.width, height: cardSize.height)
            mapBackground
            vignette
            markers
            content
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipped()
        .colorScheme(.dark)
    }

    // MARK: - Basemap

    private var mapBackground: some View {
        Group {
            if let img = snapshot?.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: mapSize.width, height: mapSize.height)
                    .clipped()
            } else {
                Color(hex: "131313")
                    .frame(width: mapSize.width, height: mapSize.height)
                    .overlay(
                        Image(systemName: "map.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Color.primaryFixed.opacity(0.12))
                    )
            }
        }
    }

    // Dark vignette top & bottom so brand and meta stay legible over the map.
    private var vignette: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "131313").opacity(0.92), location: 0.00),
                .init(color: Color(hex: "131313").opacity(0.30), location: 0.22),
                .init(color: .clear,                              location: 0.42),
                .init(color: .clear,                              location: 0.52),
                .init(color: Color(hex: "131313").opacity(0.55), location: 0.66),
                .init(color: Color(hex: "131313").opacity(0.97), location: 0.82),
                .init(color: Color(hex: "131313"),                location: 1.00)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Named route markers

    private var markers: some View {
        let placed = placedMarkers
        return ZStack(alignment: .topLeading) {
            // Leader lines for labels pushed away from their dot by collision resolution.
            ForEach(placed) { m in
                if abs(m.labelCenter.y - (m.dot.y + Self.defaultLabelOffset)) > 4 {
                    Path { p in
                        p.move(to: m.dot)
                        p.addLine(to: m.labelCenter)
                    }
                    .stroke(m.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            // Name pills — width-capped, wrapping onto up to two lines so long
            // stop names stay inside the card instead of being clipped at the edge.
            ForEach(placed) { m in
                Text(m.name.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .lineLimit(Self.maxLabelLines)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                    .frame(width: m.textWidth)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: m.height / 2)
                            .fill(Color(hex: "131313").opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: m.height / 2)
                                    .stroke(m.color.opacity(0.7), lineWidth: 1)
                            )
                    )
                    .position(m.labelCenter)
            }
            // Dots drawn last so a pin is never hidden behind another marker's pill.
            ForEach(placed) { m in
                Circle()
                    .fill(m.color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(hex: "131313"), lineWidth: 2.5))
                    .shadow(color: m.color.opacity(0.6), radius: 4)
                    .position(m.dot)
            }
        }
        .frame(width: mapSize.width, height: mapSize.height, alignment: .topLeading)
    }

    // MARK: - Collision-resolved marker layout

    private struct PlacedMarker: Identifiable {
        let id: Int
        let name: String
        let color: Color
        let dot: CGPoint
        let labelCenter: CGPoint
        let textWidth: CGFloat   // inner text frame width (excludes horizontal padding)
        let height: CGFloat      // full pill height (grows when the name wraps)
    }

    private static let defaultLabelOffset: CGFloat = -16   // label sits above its dot by default
    private static let maxLabelLines = 2
    private static let maxLabelWidth: CGFloat = 132        // full pill width cap, incl. padding
    private static let labelCharWidth: CGFloat = 6.2       // per-char advance at 9pt monospaced
    private static let labelLineHeight: CGFloat = 11       // per line at 9pt
    private static let labelHPadding: CGFloat = 14         // 7pt each side
    private static let labelVPadding: CGFloat = 6          // 3pt top+bottom

    private func markerColor(_ type: String) -> Color {
        switch type {
        case "START":       return Color.tertiaryFixed
        case "DESTINATION": return Color.primaryFixed
        default:            return .white
        }
    }

    /// Projects every waypoint, then places each name pill in the first candidate slot
    /// (above the dot, then below, then further out) that clears already-placed pills
    /// and every dot — so labels never overlap each other or cover a pin.
    private var placedMarkers: [PlacedMarker] {
        guard let snap = snapshot else { return [] }
        let sorted = waypoints.sorted { $0.order < $1.order }

        let gap: CGFloat = 3
        // Try above first, then below, then progressively further from the dot.
        let offsets: [CGFloat] = [-16, 18, -36, 38, -56, 58, -78, 80]

        let dots: [(wp: Waypoint, p: CGPoint)] = sorted.map { wp in
            (wp, snap.point(for: CLLocationCoordinate2D(latitude: wp.lat, longitude: wp.lng)))
        }

        // Seed obstacles with every dot so labels avoid covering pins.
        var obstacles: [CGRect] = dots.map { CGRect(x: $0.p.x - 8, y: $0.p.y - 8, width: 16, height: 16) }

        var result: [PlacedMarker] = []
        for d in dots {
            // Size the pill for this name, wrapping onto up to `maxLabelLines`
            // and capping total width so it never runs off the card.
            let maxTextWidth = Self.maxLabelWidth - Self.labelHPadding
            let intrinsic = CGFloat(d.wp.name.count) * Self.labelCharWidth
            let lines = min(Self.maxLabelLines, max(1, Int((intrinsic / maxTextWidth).rounded(.up))))
            let textWidth = lines == 1 ? intrinsic : maxTextWidth
            let w = textWidth + Self.labelHPadding
            let labelH = CGFloat(lines) * Self.labelLineHeight + Self.labelVPadding

            let minY: CGFloat = labelH / 2 + 6
            let maxY: CGFloat = mapSize.height - labelH / 2 - 6
            let cx = min(max(d.p.x, w / 2 + 8), cardSize.width - w / 2 - 8)

            func rect(at cy: CGFloat) -> CGRect {
                CGRect(x: cx - w / 2 - gap, y: cy - labelH / 2 - gap, width: w + 2 * gap, height: labelH + 2 * gap)
            }

            var chosenY: CGFloat?
            for off in offsets {
                let cy = d.p.y + off
                guard cy - labelH / 2 >= minY, cy + labelH / 2 <= maxY else { continue }
                if !obstacles.contains(where: { $0.intersects(rect(at: cy)) }) {
                    chosenY = cy
                    break
                }
            }
            // Fallback: no clear slot — keep the default offset, clamped in-bounds.
            let finalY = chosenY ?? min(max(d.p.y + Self.defaultLabelOffset, minY), maxY)
            obstacles.append(rect(at: finalY))

            result.append(PlacedMarker(
                id: d.wp.order,
                name: d.wp.name,
                color: markerColor(d.wp.type),
                dot: d.p,
                labelCenter: CGPoint(x: cx, y: finalY),
                textWidth: textWidth,
                height: labelH
            ))
        }
        return result
    }

    // MARK: - Foreground content

    private var content: some View {
        VStack(spacing: 0) {
            brand
                .padding(.top, 30)
            hero
                .padding(.top, 4)
            Spacer(minLength: 0)
            statRow
                .padding(.bottom, 18)
            metaBlock
            footer
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("CONVOTRACK")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundColor(.white)
        }
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(distanceKm)
                .font(.system(size: 60, weight: .black))
                .foregroundColor(Color.primaryFixed)
            Text("KM")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(Color.primaryFixed)
        }
        .shadow(color: Color.primaryFixed.opacity(0.35), radius: 16)
    }

    // Single inline stat line — the poster's "25 LAPS   250 BURPESS   $5,000 PRIZE".
    private var statRow: some View {
        HStack(spacing: 0) {
            stat(value: durationFormatted, unit: durationUnit, label: "DURATION")
            divider
            stat(value: avgSpeedKmh, unit: "KMH", label: "AVG SPEED")
            if riderCount > 0 {
                divider
                stat(value: "\(riderCount)", unit: "", label: "RIDERS")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func stat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.onSurfaceVariant)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(Color.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primaryFixed.opacity(0.35))
            .frame(width: 1, height: 26)
    }

    // Bottom meta — the poster's big tracked uppercase location/date rows.
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 10, weight: .bold))
                Text("RIDE COMPLETED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                if !dateText.isEmpty {
                    Text("· \(dateText.uppercased())")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
            }
            .foregroundColor(Color.tertiaryFixed)

            Text(rideTitle.uppercased())
                .font(.system(size: 30, weight: .black))
                .tracking(1)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let route = routeEndpoints {
                Text(route)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Color.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var routeEndpoints: String? {
        let sorted = waypoints.sorted { $0.order < $1.order }
        guard let start = sorted.first?.name, let end = sorted.last?.name, start != end else { return nil }
        var line = "\(start.uppercased())  →  \(end.uppercased())"
        let stops = max(sorted.count - 2, 0)
        if stops > 0 { line += "  (+\(stops) STOP\(stops == 1 ? "" : "S"))" }
        return line
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .fill(Color.primaryFixed.opacity(0.5))
                .frame(height: 1)
            if let qr = qrImage {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .padding(4)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("SCAN TO\nDOWNLOAD")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(Color.onSurfaceVariant)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }
}
