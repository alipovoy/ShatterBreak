import Foundation

/// Owns the countdown mechanics for a single interval: the active deadline, the
/// frozen remaining time when paused, and the expiry scheduling delegated to the
/// injected `CountdownScheduler`.
///
/// The state machine in `TimerState` decides *when* to start, freeze, or clear a
/// countdown; this type only tracks elapsed time and asks the scheduler to fire
/// `onExpiry` when the interval runs out.
@MainActor
final class Countdown {
    private let scheduler: any CountdownScheduler

    /// The wall-clock moment the current interval ends, or `nil` when frozen or cleared.
    private var deadline: Date?

    /// The remaining time captured when the countdown is not actively running.
    private var frozenRemaining: TimeInterval = 0

    init(scheduler: any CountdownScheduler) {
        self.scheduler = scheduler
    }

    /// The scheduler's current notion of "now".
    var now: Date { scheduler.now }

    /// The remaining time at `referenceDate`: derived from the deadline while
    /// active, otherwise the frozen value.
    func remaining(at referenceDate: Date) -> TimeInterval {
        guard let deadline else { return frozenRemaining }
        return max(0, deadline.timeIntervalSince(referenceDate))
    }

    /// Starts counting down for `duration`, invoking `onExpiry` when it elapses.
    func begin(for duration: TimeInterval, onExpiry: @escaping @MainActor @Sendable () -> Void) {
        let clampedDuration = max(0, duration)
        frozenRemaining = clampedDuration
        deadline = scheduler.now.addingTimeInterval(clampedDuration)
        scheduler.scheduleExpiry(after: clampedDuration, onExpiry)
    }

    /// Freezes the countdown, preserving the remaining time and dropping the deadline.
    func freeze() {
        frozenRemaining = remaining(at: scheduler.now)
        scheduler.cancelExpiry()
        deadline = nil
    }

    /// Clears all countdown state back to zero.
    func clear() {
        frozenRemaining = 0
        scheduler.cancelExpiry()
        deadline = nil
    }
}
