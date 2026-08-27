import Foundation

@testable import ShatterBreak

/// A `TimerClock` driven by hand, so tests stay fast and deterministic.
///
/// The three ways time can pass are kept apart, because the reducer distinguishes them:
///
/// - ``advance(by:)`` — awake and reconciling, the ordinary tick.
/// - ``elapse(by:)`` — awake, nothing reconciled. Both clocks move, so this is a lost
///   boundary timer or App Nap, *not* an absence.
/// - ``sleepMachine(by:)`` — asleep: wall time moves, awake time does not.
///
/// The callback is retained across ticks: nothing in this design is a one-shot, so a fake
/// that spent its callback would model a failure mode that no longer exists.
@MainActor
final class ManualTimerClock: TimerClock {
    private(set) var date: Date
    private(set) var awakeUptime: TimeInterval
    private var onReconcile: (@MainActor @Sendable () -> Void)?
    private(set) var scheduledBoundary: TimeInterval?
    private(set) var heartbeatRequested = false

    nonisolated init(now: Date = .init(timeIntervalSince1970: 0)) {
        self.date = now
        self.awakeUptime = 10_000
    }

    var instant: TimerInstant { TimerInstant(date: date, awakeUptime: awakeUptime) }

    func schedule(
        nextBoundary: TimeInterval?,
        heartbeat: Bool,
        _ onReconcile: @escaping @MainActor @Sendable () -> Void
    ) {
        self.scheduledBoundary = nextBoundary
        self.heartbeatRequested = heartbeat
        self.onReconcile = onReconcile
    }

    func stop() {
        onReconcile = nil
        scheduledBoundary = nil
        heartbeatRequested = false
    }

    func advance(by interval: TimeInterval = 1) {
        elapse(by: interval)
        onReconcile?()
    }

    func elapse(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
        awakeUptime += interval
    }

    func sleepMachine(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
    }

    /// A spurious or duplicate callback: nothing should come of it.
    func fireReconcile() {
        onReconcile?()
    }
}
