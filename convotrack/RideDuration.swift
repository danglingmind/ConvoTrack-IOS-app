import Foundation

/// The one place a ride duration becomes text.
///
/// There were two independent implementations and they had already drifted.
/// `RideHistoryView` formatted *every* duration as `"%d:%02d HRS"` unconditionally, so a
/// 44-minute ride rendered **"0:44 HRS"** — a minutes-long ride labelled in hours. The summary
/// screen had its own pair (`formatDuration` / `durationUnit`) which was at least internally
/// consistent, but anything over an hour came out as "1:44" beside a "HRS" label, and that is
/// ambiguous on sight: 1.44 hours? one hour forty-four? a clock time?
///
/// Value and unit are returned together here so they can never be derived from different inputs,
/// and every surface — the summary metrics, the shareable image, the history list — reads from
/// this single switch.
///
/// What the number means is decided server-side (`summaryService.ts`): actual wall-clock
/// `endedAt − startedAt`, which starts when the leader taps START RIDE and includes any time
/// paused or stopped. This type only renders it.
enum RideDuration {

    /// Big-value + small-caps-unit pair, for `MetricCard` and the share card.
    static func stat(_ seconds: Int?) -> (value: String, unit: String) {
        guard let seconds, seconds > 0 else { return ("--", "") }
        switch seconds {
        case ..<60:
            return ("\(seconds)", "SEC")
        case ..<3600:
            return ("\(seconds / 60)", "MIN")
        default:
            // The unit spells out the format, because "1:44 HRS" is exactly the ambiguity that
            // started this. Hours are deliberately not capped at 24 — a ride nobody remembered
            // to end reads "26:10", which looks wrong because it is wrong.
            return (String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60), "H:MM")
        }
    }

    /// Single inline string, for rows with no separate unit slot.
    static func inline(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        if seconds < 60   { return "\(seconds) SEC" }
        if seconds < 3600 { return "\(seconds / 60) MIN" }
        return String(format: "%dH %02dM", seconds / 3600, (seconds % 3600) / 60)
    }
}
