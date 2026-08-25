import Foundation

/// Owns the countdown mechanics for a single interval: the active deadline, the
/// frozen remaining time when paused, and the expiry scheduling delegated to the
/// injected `CountdownScheduler`.
///
/// `TimerState` decides *when* to start, freeze, or clear a countdown; this type
/// only tracks elapsed time and asks the scheduler to fire `onExpiry`.
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

    /// How far past the deadline `referenceDate` is, or `nil` with no countdown active.
    ///
    /// Unlike ``remaining(at:)``, which clamps at zero for display, this keeps counting
    /// so callers can tell an expiry in flight from one that never fired.
    func overdue(at referenceDate: Date) -> TimeInterval? {
        deadline.map(referenceDate.timeIntervalSince)
    }

    /// Starts counting down for `duration`, invoking `onExpiry` when it elapses.
    func begin(for duration: TimeInterval, onExpiry: @escaping @MainActor @Sendable () -> Void) {
        let clampedDuration = max(0, duration)
        frozenRemaining = clampedDuration
        deadline = scheduler.now.addingTimeInterval(clampedDuration)
        armExpiry(after: clampedDuration, onExpiry)
    }

    /// Schedules the expiry callback, re-arming it if it arrives before the deadline.
    ///
    /// The scheduler owes exactly one callback but does not measure the same time
    /// `remaining(at:)` does: the deadline is on the wall clock, while
    /// `SystemCountdownScheduler` waits on `Task.sleep`'s monotonic clock. NTP slew is
    /// enough to make them disagree. Passing an early callback on would spend the one
    /// shot for nothing — the caller sees time left, declines to transition, and nothing
    /// re-arms — so the countdown would run out unobserved and drop every later
    /// transition. Each pass waits out a residual the clocks can only disagree over by a
    /// fraction of itself, so this settles rather than loops.
    private func armExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    ) {
        scheduler.scheduleExpiry(after: delay) { [weak self] in
            guard let self else { return }

            // No deadline means `freeze()` or `clear()` won the race with a callback
            // already past cancellation, and neither wants an expiry.
            guard let deadline else { return }

            let remaining = deadline.timeIntervalSince(scheduler.now)
            guard remaining <= 0 else {
                armExpiry(after: remaining, onExpiry)
                return
            }

            onExpiry()
        }
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
