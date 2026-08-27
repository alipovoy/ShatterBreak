import Foundation

/// Supplies the current moment and asks to be called back to reconcile.
///
/// Note what it does *not* promise: punctuality, or even firing at all. Reconciling is
/// idempotent, so an early, late or missing callback costs at most a tick — which is why
/// the old design's stall detection and Resume button have no successor.
@MainActor
protocol TimerClock: AnyObject {
    var instant: TimerInstant { get }

    /// Asks to be called back, replacing any previous request.
    ///
    /// - Parameters:
    ///   - nextBoundary: seconds until the next transition is due, or `nil` when no
    ///     countdown is running.
    ///   - heartbeat: whether to keep checking in regardless. Not the same question as
    ///     `nextBoundary != nil`: a break held back from a dark screen has no countdown but
    ///     still needs a retry.
    func schedule(
        nextBoundary: TimeInterval?,
        heartbeat: Bool,
        _ onReconcile: @escaping @MainActor @Sendable () -> Void
    )

    /// Stops all scheduled work.
    func stop()
}

/// A punctual boundary timer, plus a coalesced heartbeat behind it.
///
/// - The **boundary timer** is armed for exactly the time left, and is the thing that
///   historically went missing (#106, #107).
/// - The **heartbeat** is the safety net: coarse and tolerant so the system coalesces it,
///   and armed only while something is pending, so an idle app schedules nothing.
///
/// A heartbeat alone was rejected — it would park the menu bar at 00:00 for up to half a
/// minute at every transition (#108). A boundary timer alone is what the app had.
@MainActor
final class SystemTimerClock: TimerClock {
    /// Long enough to coalesce, short enough that a lost boundary timer is a hiccup.
    static let heartbeatPeriod: TimeInterval = 30
    /// Slack, so the system folds this into wake-ups it was making anyway.
    static let heartbeatTolerance: Duration = .seconds(10)
    /// Tight: this one is what the user sees land.
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
        // Left running across boundaries: re-creating it would reset its phase, and its
        // whole value is being the timer nothing else touches.
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
