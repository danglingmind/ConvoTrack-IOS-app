import ActivityKit
import Foundation

/// Owns the ride's Live Activity (Lock Screen + Dynamic Island). Updated locally while the app runs
/// in the background on its `location` / `audio` modes; no push tokens or backend involved (v1).
///
/// Updates are throttled to one per `minInterval`, except a step change or an emergency
/// starting/ending, which go out at once. A throttled update isn't dropped: the latest one is held
/// and sent when the window opens, so the activity never rests on stale numbers.
@MainActor
final class RideLiveActivityController {
    typealias State = RideActivityAttributes.ContentState

    static let shared = RideLiveActivityController()
    private static let minInterval: TimeInterval = 5

    private var activity: Activity<RideActivityAttributes>?
    private var lastSent: State?
    private var lastSentAt: Date = .distantPast
    private var pending: State?
    private var flushTask: Task<Void, Never>?
    /// Bumped by `end()` so a `start()` still awaiting the system can tell it has been cancelled.
    private var generation = 0

    private init() {}

    var isRunning: Bool { activity != nil }

    /// Starts the activity for `rideId`, first ending any left over from a previous run (a crash or
    /// force-quit leaves the old one on the Lock Screen). Safe to call again for the same ride.
    func start(rideId: String, destinationName: String, state: State) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let current = activity, current.attributes.rideId == rideId, current.activityState == .active {
            update(state)
            return
        }
        let gen = generation
        Task { [weak self] in
            // Stale activities from an earlier launch (or another ride) go first.
            for old in Activity<RideActivityAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            guard let self, self.generation == gen else { return }
            do {
                let content = ActivityContent(state: state, staleDate: nil)
                let created = try Activity.request(
                    attributes: RideActivityAttributes(rideId: rideId, destinationName: destinationName),
                    content: content,
                    pushType: nil
                )
                guard self.generation == gen else {
                    await created.end(nil, dismissalPolicy: .immediate)
                    return
                }
                self.activity = created
                self.lastSent = state
                self.lastSentAt = Date()
            } catch {
                // Too many activities, disabled in Settings, etc. The in-app UI is unaffected.
                self.activity = nil
            }
        }
    }

    func update(_ state: State) {
        guard activity != nil else { return }
        if let last = lastSent, Self.sameContent(last, state) { pending = nil; return }

        let urgent = lastSent.map { Self.isUrgent(from: $0, to: state) } ?? true
        let wait = Self.minInterval - Date().timeIntervalSince(lastSentAt)
        if urgent || wait <= 0 {
            send(state)
        } else {
            pending = state
            guard flushTask == nil else { return }
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.flushTask = nil
                if let latest = self.pending { self.send(latest) }
            }
        }
    }

    func end() {
        generation += 1
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        lastSent = nil
        let finished = activity
        activity = nil
        Task {
            await finished?.end(nil, dismissalPolicy: .immediate)
            // Anything else we own (a start() still in flight, a stale one) goes too.
            for leftover in Activity<RideActivityAttributes>.activities {
                await leftover.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Private

    private func send(_ state: State) {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        lastSent = state
        lastSentAt = Date()
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// A new step or an emergency starting/ending can't wait for the throttle window.
    private static func isUrgent(from old: State, to new: State) -> Bool {
        old.maneuver != new.maneuver
            || old.instruction != new.instruction
            || (old.emergencyName == nil) != (new.emergencyName == nil)
    }

    /// Equality ignoring the `arrival` Date (it drifts every tick; `arrivalText` carries what is shown).
    private static func sameContent(_ a: State, _ b: State) -> Bool {
        var b = b
        b.arrival = a.arrival
        return a == b
    }
}
