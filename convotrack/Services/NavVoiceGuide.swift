import Foundation

/// Decides WHEN the next maneuver is spoken, and what is said.
///
/// A rider can't look at the turn card at road speed, so each maneuver is announced up to four
/// times as it approaches: a far heads-up, the main prompt, a short reminder, and "now". Distances
/// grow with speed so the prompt always leaves roughly the same lead time, not the same distance.
///
/// Pure logic: it holds no audio and no clock, so it can be driven by a unit test. The Android
/// `NavVoiceGuide` mirrors it; keep thresholds and wording in step.
struct NavVoiceGuide {
    struct Input {
        /// Identifies the maneuver being approached; a new value starts a fresh set of prompts.
        let key: Int
        let distanceMeters: Double
        let speedKmh: Double
        let instruction: String
        let maneuver: String
        /// The maneuver after this one, only when it follows closely (see `thenWithinMeters`).
        let thenManeuver: String?
    }

    private enum Level: Int { case far = 1, mid, near, now }

    /// "In 1.2 kilometres…" is only worth saying when the turn is at least this far off.
    static let farMinMeters = 800.0
    static let midBaseMeters = 500.0
    static let nearBaseMeters = 100.0
    static let nowMeters = 15.0
    static let arriveNowMeters = 30.0
    /// Lead time the speed-scaled prompts aim for, in seconds.
    static let midLeadSeconds = 20.0
    static let nearLeadSeconds = 6.0
    /// A second maneuver closer than this after the first is spoken with it ("…then turn left").
    static let thenWithinMeters = 150.0

    private var key: Int?
    private var spoken = 0
    private var last: Input?

    mutating func reset() {
        key = nil
        spoken = 0
        last = nil
    }

    /// Returns the sentence to speak now, or nil.
    mutating func update(_ input: Input) -> String? {
        last = input
        if key != input.key {
            key = input.key
            spoken = 0
        }
        guard input.distanceMeters > 0 || input.maneuver == "ARRIVE" else { return nil }
        let level = Self.level(for: input)
        guard level.rawValue > spoken else { return nil }
        spoken = level.rawValue
        // The far prompt is skipped (but counted) when the turn is closer than it is useful for.
        if level == .far && input.distanceMeters < Self.farMinMeters { return nil }
        return Self.text(level: level, input)
    }

    /// The current maneuver again, for when voice is switched back on. Always a full sentence.
    func repeatCurrent() -> String? {
        guard let input = last else { return nil }
        let level = Self.level(for: input).rawValue < Level.mid.rawValue ? Level.mid : Self.level(for: input)
        return Self.text(level: level, input)
    }

    // MARK: - Levels

    private static func level(for input: Input) -> Level {
        let metersPerSecond = max(0, input.speedKmh) / 3.6
        let now = input.maneuver == "ARRIVE" ? arriveNowMeters : nowMeters
        let near = max(nearBaseMeters, metersPerSecond * nearLeadSeconds)
        let mid = max(midBaseMeters, metersPerSecond * midLeadSeconds)
        let d = input.distanceMeters
        if d <= now { return .now }
        if d <= near { return .near }
        if d <= mid { return .mid }
        return .far
    }

    // MARK: - Wording

    private static func text(level: Level, _ input: Input) -> String {
        let arriving = input.maneuver == "ARRIVE"
        switch level {
        case .far, .mid:
            let lead = "In \(spokenDistance(input.distanceMeters)), "
            return lead + (arriving ? "you will arrive at your destination" : lowerFirst(input.instruction))
        case .near:
            if arriving { return "Your destination is just ahead" }
            var sentence = input.instruction
            if let then = input.thenManeuver, let phrase = phrase(for: then) {
                sentence += ", then \(phrase)"
            }
            return sentence
        case .now:
            if arriving { return "You have arrived at your destination" }
            return upperFirst(phrase(for: input.maneuver) ?? input.instruction)
        }
    }

    /// A short imperative for a Routes API maneuver; nil when the enum has nothing better than
    /// the full instruction text.
    static func phrase(for maneuver: String) -> String? {
        switch maneuver {
        case "TURN_LEFT":          return "turn left"
        case "TURN_RIGHT":         return "turn right"
        case "TURN_SHARP_LEFT":    return "turn sharp left"
        case "TURN_SHARP_RIGHT":   return "turn sharp right"
        case "TURN_SLIGHT_LEFT":   return "bear left"
        case "TURN_SLIGHT_RIGHT":  return "bear right"
        case "RAMP_LEFT":          return "take the ramp on the left"
        case "RAMP_RIGHT":         return "take the ramp on the right"
        case "UTURN_LEFT", "UTURN_RIGHT": return "make a U-turn"
        case "MERGE":              return "merge"
        case "FORK_LEFT":          return "keep left"
        case "FORK_RIGHT":         return "keep right"
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT": return "enter the roundabout"
        case "STRAIGHT", "NAME_CHANGE", "DEPART": return "continue straight"
        default:                   return nil
        }
    }

    /// "350 metres", "1.2 kilometres": rounded the way a person would say it.
    static func spokenDistance(_ meters: Double) -> String {
        if meters < 1000 {
            let r = max(50, Int((meters / 50).rounded()) * 50)
            if r < 1000 { return "\(r) metres" }
        }
        let km = (meters / 100).rounded() / 10
        if km == km.rounded() {
            let n = Int(km)
            return n == 1 ? "1 kilometre" : "\(n) kilometres"
        }
        return String(format: "%.1f kilometres", km)
    }

    private static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
    private static func upperFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
