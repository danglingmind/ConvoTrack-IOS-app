import CoreGraphics
import Foundation

// Pure, SDK-free marker de-collision.
//
// Each marker has a fixed "tip" (its true screen coordinate) and a "body" (the
// circle+label art) that in the default layout sits at `defaultCenter`. When bodies
// overlap we displace the *movable* ones — never their tips — so labels stay upright
// and connected to their tip by a leader line the renderer draws. Static stops and the
// user arrow are passed as immovable obstacles that riders spread around.
//
// Separation is axis-aligned minimal-translation (bodies treated as boxes): each
// colliding pair is pushed apart along its axis of least penetration, iterated a few
// times so clusters relax. Displacement is clamped to `maxLeader`; a very tight cluster
// keeps some residual overlap rather than flinging bodies far from their tips.
enum MarkerCollisionResolver {

    struct Marker {
        let id: String
        let tip: CGPoint            // true coordinate in screen points (fixed)
        let defaultCenter: CGPoint  // body-box center at rest (tip + default offset)
        let halfSize: CGSize        // half the body box (screen points)
        let movable: Bool
        let prevOffset: CGVector    // last frame's displacement (seed, for stability)
    }

    /// Returns the body displacement (from `defaultCenter`) for each **movable** marker.
    static func resolve(
        _ markers: [Marker],
        maxLeader: CGFloat = 60,
        padding: CGFloat = 3,
        iterations: Int = 12
    ) -> [String: CGVector] {

        guard markers.count > 1 else { return [:] }

        let ids = markers.map { $0.id }
        var pos: [String: CGPoint] = [:]
        var half: [String: CGSize] = [:]
        var movable: [String: Bool] = [:]
        var def: [String: CGPoint] = [:]
        for m in markers {
            pos[m.id] = CGPoint(x: m.defaultCenter.x + m.prevOffset.dx,
                                y: m.defaultCenter.y + m.prevOffset.dy)
            half[m.id] = m.halfSize
            movable[m.id] = m.movable
            def[m.id] = m.defaultCenter
        }

        for _ in 0..<iterations {
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let a = ids[i], b = ids[j]
                    guard movable[a]! || movable[b]! else { continue }

                    let pa = pos[a]!, pb = pos[b]!
                    let dx = pb.x - pa.x
                    let dy = pb.y - pa.y
                    let minX = half[a]!.width + half[b]!.width + padding
                    let minY = half[a]!.height + half[b]!.height + padding

                    let overlapX = minX - abs(dx)
                    let overlapY = minY - abs(dy)
                    guard overlapX > 0, overlapY > 0 else { continue }  // no box overlap

                    // Push along the axis of least penetration.
                    var pushX: CGFloat = 0, pushY: CGFloat = 0
                    if overlapX < overlapY {
                        let sign: CGFloat = abs(dx) < 0.001 ? tieSign(a, b) : (dx < 0 ? -1 : 1)
                        pushX = overlapX * sign
                    } else {
                        let sign: CGFloat = abs(dy) < 0.001 ? tieSign(a, b) : (dy < 0 ? -1 : 1)
                        pushY = overlapY * sign
                    }

                    let bothMovable = movable[a]! && movable[b]!
                    if bothMovable {
                        pos[a]!.x -= pushX / 2; pos[a]!.y -= pushY / 2
                        pos[b]!.x += pushX / 2; pos[b]!.y += pushY / 2
                    } else if movable[a]! {
                        pos[a]!.x -= pushX; pos[a]!.y -= pushY
                    } else {
                        pos[b]!.x += pushX; pos[b]!.y += pushY
                    }
                }
            }

            // Keep every movable body within maxLeader of its tip.
            for id in ids where movable[id]! {
                var ox = pos[id]!.x - def[id]!.x
                var oy = pos[id]!.y - def[id]!.y
                let mag = (ox * ox + oy * oy).squareRoot()
                if mag > maxLeader {
                    ox = ox / mag * maxLeader
                    oy = oy / mag * maxLeader
                    pos[id]!.x = def[id]!.x + ox
                    pos[id]!.y = def[id]!.y + oy
                }
            }
        }

        var out: [String: CGVector] = [:]
        for id in ids where movable[id]! {
            let v = CGVector(dx: pos[id]!.x - def[id]!.x, dy: pos[id]!.y - def[id]!.y)
            // Only report a meaningful displacement.
            out[id] = (abs(v.dx) < 0.5 && abs(v.dy) < 0.5) ? .zero : v
        }
        return out
    }

    // Deterministic ±1 so two markers sharing an exact coordinate always separate the
    // same way frame-to-frame (no flicker).
    private static func tieSign(_ a: String, _ b: String) -> CGFloat {
        ((a < b ? a + b : b + a).hashValue & 1) == 0 ? 1 : -1
    }
}
