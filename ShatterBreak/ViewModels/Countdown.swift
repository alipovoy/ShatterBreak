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
        armExpiry(after: clampedDuration, onExpiry)
    }

    /// Schedules the expiry callback, re-arming it if it arrives before the deadline.
    ///
    /// The scheduler owes exactly one callback per `scheduleExpiry`, but it does not
    /// measure the same time `remaining(at:)` does: the deadline is a `Date` on the wall
    /// clock, while `SystemCountdownScheduler` waits on `Task.sleep`'s monotonic clock.
    /// The two need only disagree by a fraction of a second — the wall clock being slewed
    /// to correct NTP offset is enough — for the callback to arrive with time still on
    /// the countdown.
    ///
    /// Passing that early callback on would spend the one shot for nothing: the caller
    /// sees time remaining, declines to transition, and no further callback is ever
    /// scheduled. The countdown then runs out unobserved and the timer sits at its
    /// expired display forever, dropping every transition after it. So an early callback
    /// re-arms for the time the wall clock still shows instead. Each pass waits out a
    /// residual the clocks can only disagree over by a fraction of itself, so this
    /// settles within a pass or two rather than looping; and `scheduleExpiry` replaces
    /// any pending callback, so a `begin` that lands mid-flight supersedes it rather
    /// than racing it.
    private func armExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    ) {
        scheduler.scheduleExpiry(after: delay) { [weak self] in
            guard let self else { return }

            // No deadline means `freeze()` or `clear()` won the race with a callback
            // already past cancellation. Neither wants an expiry: the frozen remainder
            // resumes through `begin`, and a cleared countdown owes nothing at all.
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
