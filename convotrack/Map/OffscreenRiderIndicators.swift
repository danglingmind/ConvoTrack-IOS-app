import SwiftUI
import CoreGraphics

// MARK: - Geometry emitted by the map coordinator

/// Pure screen geometry for one off-screen rider, produced inside
/// `GoogleMapView.Coordinator` (the only place `GMSMapView.projection` is
/// reachable). Rider metadata (name/avatar/offline) is joined back in SwiftUI.
struct EdgeIndicator: Identifiable, Equatable {
    let id: String              // rider id
    let edgePoint: CGPoint      // clamped point on the screen edge, in map-view coords
    let arrowAngle: CGFloat     // atan2(dy, dx) of the direction toward the rider (y down)
    let distanceMeters: Double
}

// MARK: - Merged view models

/// An `EdgeIndicator` joined with the rider's display metadata.
struct EdgeChipModel: Identifiable, Equatable {
    let id: String
    let name: String
    let avatarUrl: String?
    let isOffline: Bool
    let edgePoint: CGPoint
    let arrowAngle: CGFloat
    let distanceMeters: Double
}

/// A group of chips that clamp to nearly the same screen position.
struct EdgeCluster: Identifiable {
    let id: String              // stable-ish: nearest member's rider id
    let members: [EdgeChipModel]
    let anchor: CGPoint         // where the (collapsed) chip is drawn
    let arrowAngle: CGFloat     // nearest member's direction
    let minDistance: Double     // closest member — shown on the cluster chip
}

/// Greedy grouping of edge chips whose anchor points fall within `radius`
/// points of each other. Members are seeded nearest-first so the closest rider
/// anchors each cluster.
func clusterIndicators(_ chips: [EdgeChipModel], radius: CGFloat = 60) -> [EdgeCluster] {
    let sorted = chips.sorted { $0.distanceMeters < $1.distanceMeters }
    var assigned = Set<String>()
    var clusters: [EdgeCluster] = []

    for seed in sorted where !assigned.contains(seed.id) {
        assigned.insert(seed.id)
        var members = [seed]
        for other in sorted where !assigned.contains(other.id) {
            if hypot(other.edgePoint.x - seed.edgePoint.x,
                     other.edgePoint.y - seed.edgePoint.y) <= radius {
                assigned.insert(other.id)
                members.append(other)
            }
        }
        clusters.append(EdgeCluster(
            id: seed.id,
            members: members,
            anchor: seed.edgePoint,
            arrowAngle: seed.arrowAngle,
            minDistance: members.map(\.distanceMeters).min() ?? seed.distanceMeters
        ))
    }
    return clusters
}

// MARK: - Overlay

/// SwiftUI layer that draws one chip per cluster over the nav map. Collapsed
/// clusters (>1 rider) show a count + minimum distance; tapping fans them out
/// into individual chips. Tapping a single/expanded chip flies the camera to
/// that rider via `onTapRider`.
struct OffscreenIndicatorsOverlay: View {
    let clusters: [EdgeCluster]
    let onTapRider: (String) -> Void

    @State private var expandedClusterId: String? = nil

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                // Dismiss the expanded fan by tapping elsewhere.
                if expandedClusterId != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { expandedClusterId = nil }
                }

                ForEach(clusters) { cluster in
                    if cluster.id == expandedClusterId && cluster.members.count > 1 {
                        fannedCluster(cluster, center: center)
                    } else if cluster.members.count > 1 {
                        ClusterChip(count: cluster.members.count,
                                    distanceMeters: cluster.minDistance)
                            .position(cluster.anchor)
                            .onTapGesture { expandedClusterId = cluster.id }
                    } else if let only = cluster.members.first {
                        EdgeChip(model: only)
                            .position(cluster.anchor)
                            .onTapGesture { onTapRider(only.id) }
                    }
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: expandedClusterId)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    /// Members stacked toward screen interior from the cluster anchor.
    private func fannedCluster(_ cluster: EdgeCluster, center: CGPoint) -> some View {
        // Unit vector pointing inward (anchor → screen center).
        let dx = center.x - cluster.anchor.x
        let dy = center.y - cluster.anchor.y
        let len = max(hypot(dx, dy), 0.001)
        let inward = CGVector(dx: dx / len, dy: dy / len)

        return ForEach(Array(cluster.members.enumerated()), id: \.element.id) { idx, member in
            let step = CGFloat(idx) * 46
            let pt = CGPoint(x: cluster.anchor.x + inward.dx * step,
                             y: cluster.anchor.y + inward.dy * step)
            EdgeChip(model: member)
                .position(pt)
                .onTapGesture { onTapRider(member.id) }
        }
    }
}

// MARK: - Chips

private func formatEdgeDistance(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10)m" }
    return String(format: "%.1fkm", meters / 1000)
}

/// Single off-screen rider: avatar ringed in the theme green, distance underneath.
///
/// Deliberately card-less. These sit over a moving map, and a filled panel behind each one hid
/// more road than the rider it was pointing at. The ring carries the identity, the shadow keeps
/// both legible over light and dark map tiles, and nothing else competes with the route.
struct EdgeChip: View {
    let model: EdgeChipModel
    private var size: CGFloat { 34 }

    var body: some View {
        VStack(spacing: 3) {
            avatar
            Text(formatEdgeDistance(model.distanceMeters))
                .font(.dataMono)
                .foregroundColor(Color.onSurface)
                .lineLimit(1)
                // Shadow instead of a plate: legible over any map tile, hides nothing.
                .shadow(color: .black.opacity(0.85), radius: 3)
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
        .opacity(model.isOffline ? 0.55 : 1)
    }

    private var avatar: some View {
        Group {
            if let url = model.avatarUrl.flatMap(URL.init) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { Circle().fill(Color.surfaceVariant) }
            } else {
                Circle().fill(Color.surfaceVariant)
                    .overlay(
                        Text(String(model.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundColor(Color.onSurface)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.tertiaryFixed, lineWidth: 2))
        .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
    }
}

/// Collapsed cluster: rider count in a ringed circle, minimum distance underneath. Same
/// card-less treatment as `EdgeChip`, so a cluster reads as "several of those" rather than as a
/// different kind of object.
struct ClusterChip: View {
    let count: Int
    let distanceMeters: Double
    private var size: CGFloat { 34 }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(Color.onSurface)
                .frame(width: size, height: size)
                .background(Color.surfaceVariant)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.tertiaryFixed, lineWidth: 2))
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
            Text(formatEdgeDistance(distanceMeters))
                .font(.dataMono)
                .foregroundColor(Color.onSurface)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.85), radius: 3)
                .shadow(color: .black.opacity(0.6), radius: 1)
        }
    }
}
