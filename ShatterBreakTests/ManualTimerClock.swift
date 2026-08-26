import Foundation

@testable import ShatterBreak

/// A `TimerClock` driven by hand, so tests stay fast and deterministic.
///
/// The three ways time can pass are separate, because they are separate in reality and the
/// reducer distinguishes them:
///
/// - ``advance(by:)`` — awake and reconciling, the ordinary tick.
/// - ``elapse(by:)`` — awake, but nothing reconciled. Both clocks move, so this is *not*
///   an absence: it is a lost boundary timer, a throttled heartbeat, App Nap.
/// - ``sleepMachine(by:)`` — the machine was asleep. Wall time moves and awake time does
///   not, which is what `ProcessInfo.systemUptime` does for real.
///
/// Unlike the one-shot scheduler it replaces, the callback is *retained* across ticks.
/// That is not a convenience: in the new design nothing is a one-shot, so a fake that
/// spent its callback would be modelling a failure mode that no longer exists.
@MainActor
final class ManualTimerClock: TimerClock {
    private(set) var date: Date
    private(set) var awakeUptime: TimeInterval
    private var onReconcile: (@MainActor @Sendable () -> Void)?
    /// The boundary the state last asked to be woken for, so tests can assert punctuality.
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

    /// Reconciles without moving either clock, the way a spurious or duplicate callback
    /// does. Nothing should come of it.
    func fireReconcile() {
        onReconcile?()
    }
}
