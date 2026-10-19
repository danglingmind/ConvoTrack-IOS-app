import ActivityKit
import Foundation

/// Live Activity model shared by the app (which updates it) and the widget extension (which draws
/// it). Compiled into BOTH targets, so it must stay free of app-only dependencies.
///
/// The Lock Screen is public, so nothing here identifies a rider beyond a first name and only
/// while an emergency is open, and no coordinates are carried.
nonisolated struct RideActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// Routes API maneuver enum ("TURN_LEFT"...); mapped to an SF Symbol by `symbolName`.
        var maneuver: String
        /// "350 m" / "1.2 km"; empty when there is no upcoming turn.
        var distanceText: String
        /// Street / instruction for the next maneuver.
        var instruction: String
        /// Estimated arrival at the next stop.
        var arrival: Date
        /// Arrival clock digits without AM/PM ("10:42"), for the narrow compact slot.
        var arrivalText: String
        /// "42m left".
        var timeLeftText: String
        /// Metres between the leader and the last rider when the convoy is stretched; nil when fine.
        var convoyGapMeters: Double?
        /// First name of the rider who raised an open emergency; nil when none.
        var emergencyName: String?

        var symbolName: String {
            RideActivityManeuver.symbol(for: maneuver, instruction: instruction)
        }

        var convoyText: String? {
            guard let gap = convoyGapMeters, gap > 0 else { return nil }
            return "Last rider −\(RideActivityManeuver.distanceText(gap))"
        }

        /// Short, public-safe emergency line.
        var emergencyText: String? {
            emergencyName.map { $0 == "You" ? "You need help" : "\($0) needs help" }
        }
    }

    var rideId: String
    var destinationName: String
}

/// Same mapping as the in-app turn card (`RideNavigationView.maneuverIcon`); copied here so the
/// extension can use it. Keep the two in step.
nonisolated enum RideActivityManeuver {
    static func symbol(for maneuver: String, instruction: String) -> String {
        switch maneuver {
        case "TURN_LEFT", "TURN_SHARP_LEFT":   return "arrow.turn.up.left"
        case "TURN_RIGHT", "TURN_SHARP_RIGHT": return "arrow.turn.up.right"
        case "TURN_SLIGHT_LEFT", "RAMP_LEFT":  return "arrow.up.left"
        case "TURN_SLIGHT_RIGHT", "RAMP_RIGHT": return "arrow.up.right"
        case "UTURN_LEFT":                     return "arrow.uturn.left"
        case "UTURN_RIGHT":                    return "arrow.uturn.right"
        case "MERGE":                          return "arrow.merge"
        case "FORK_LEFT", "FORK_RIGHT":        return "arrow.triangle.branch"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT":
            return "arrow.triangle.turn.up.right.circle"
        case "FERRY", "FERRY_TRAIN":           return "ferry"
        case "DEPART", "STRAIGHT", "NAME_CHANGE": return "arrow.up"
        case "ARRIVE":                         return "flag.checkered"
        default:                               return legacy(for: instruction)
        }
    }

    private static func legacy(for instruction: String) -> String {
        let l = instruction.lowercased()
        if l.contains("arrive") || l.contains("destination") { return "flag.checkered" }
        if l.contains("u-turn") || l.contains("uturn") { return "arrow.uturn.left" }
        if l.contains("roundabout") || l.contains("rotary") { return "arrow.triangle.turn.up.right.circle" }
        if l.contains("merge") { return "arrow.merge" }
        if l.contains("left") { return "arrow.turn.up.left" }
        if l.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    static func distanceText(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", meters / 1000)
    }
}
