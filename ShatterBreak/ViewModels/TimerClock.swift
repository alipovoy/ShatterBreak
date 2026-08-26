import Foundation

/// Supplies the current moment and asks to be called back to reconcile.
///
/// The one test seam for time. Note what it does *not* promise: nothing here is required
/// to be punctual, or even to fire. A reconcile is idempotent and derives everything from
/// the moment it runs, so an early callback, a late one, and a missing one all cost at
/// most a tick — which is why the old design's re-arming, stall detection and Resume
/// button have no successor here.
@MainActor
protocol TimerClock: AnyObject {
    /// Now, on both clocks: wall time, and time the machine has been awake.
    var instant: TimerInstant { get }

    /// Asks to be called back, replacing any previous request.
    ///
    /// - Parameters:
    ///   - nextBoundary: seconds until the next transition is due, or `nil` when no
    ///     countdown is running.
    ///   - heartbeat: whether to keep checking in regardless. Not the same question as
    ///     `nextBoundary != nil`: a break held back from a dark screen has no countdown
    ///     left but still needs someone to come back and try again.
    func schedule(
        nextBoundary: TimeInterval?,
        heartbeat: Bool,
        _ onReconcile: @escaping @MainActor @Sendable () -> Void
    )

    /// Stops all scheduled work.
    func stop()
}

/// The production clock: a punctual boundary timer, plus a coalesced heartbeat behind it.
///
/// Two timers because one is not enough and one is too many:
///
/// - The **boundary timer** is the fast path. It is armed for exactly the time left, so
///   transitions land within a couple of hundred milliseconds — the punctuality the app
///   has always had. It is also the thing that historically went missing (#106, #107).
/// - The **heartbeat** is the safety net, and nothing more. Thirty seconds with ten
///   seconds of tolerance so the system coalesces it with other wake-ups, and only while
///   something is actually pending, so an idle app schedules nothing at all.
///
/// Neither is trusted. A heartbeat *alone* was considered and rejected: it would park the
/// menu bar at 00:00 for up to half a minute at every transition, which is exactly the
/// symptom #108 was about. A boundary timer alone is what the app had.
@MainActor
final class SystemTimerClock: TimerClock {
    /// How often the safety net checks. Long enough to coalesce, short enough that a lost
    /// boundary timer is a hiccup rather than the stall it is today.
    static let heartbeatPeriod: TimeInterval = 30
    /// Generous slack so the system can fold this into wake-ups it was making anyway.
    static let heartbeatTolerance: Duration = .seconds(10)
    /// Tight, because this one is what the user sees land.
    static let boundaryTolerance: Duration = .milliseconds(100)

    private var boundaryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    nonisolated init() {}

    var instant: TimerInstant {
        TimerInstant(date: .now, awakeUptime: ProcessInfo.processInfo.systemUptime)
    }

    func schedule(
        nextBoundary: TimeInterval?,
        heartbeat: Bool,
        _ onReconcile: @escaping @MainActor @Sendable () -> Void
    ) {
        boundaryTask?.cancel()
        boundaryTask = nil
        if let nextBoundary {
            boundaryTask = Self.after(nextBoundary, tolerance: Self.boundaryTolerance, onReconcile)
        }

        guard heartbeat else {
            heartbeatTask?.cancel()
            heartbeatTask = nil
            return
        }
        // Left running across boundaries: re-creating it on every transition would reset
        // its phase, and its whole value is being the timer nothing in the state machine
        // has a reason to touch.
        guard heartbeatTask == nil else { return }

        heartbeatTask = Task(priority: .utility) {
            while Task.isCancelled == false {
                do {
                    try await Task.sleep(
                        for: .seconds(Self.heartbeatPeriod),
                        tolerance: Self.heartbeatTolerance
                    )
                } catch {
                    return
                }
                onReconcile()
            }
        }
    }

    func stop() {
        boundaryTask?.cancel()
        boundaryTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private static func after(
        _ delay: TimeInterval,
        tolerance: Duration,
        _ body: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        Task(priority: .utility) {
            do {
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay), tolerance: tolerance)
                }
                try Task.checkCancellation()
            } catch {
                return
            }
            body()
        }
    }
}
