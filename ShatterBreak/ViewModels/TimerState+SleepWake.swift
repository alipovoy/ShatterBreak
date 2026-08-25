import Foundation
import os

/// Sleep/wake reconciliation for the timer state machine.
///
/// Split out of ``TimerState`` so the state file stays focused. The countdown never
/// freezes on sleep (issue #4); these methods note when the machine slept and, on wake,
/// reconcile against the wall-clock time spent away via the pure ``WakeOutcome``.
extension TimerState {
    /// How far past its deadline a transition must be before it reads as stalled rather
    /// than merely in flight. Comfortably clears the scheduler's 200 ms tolerance plus
    /// callback latency, and stays well under the point a user would notice.
    static let stallGrace: TimeInterval = 5

    /// Records that the system or display went to sleep.
    ///
    /// The countdown is deliberately *not* frozen: per issue #4 the timer never stops on
    /// sleep or screen lock. We only note the moment so ``handleWake()`` can measure how
    /// long the user was away. A duplicate notification (system *and* display sleep can
    /// both fire) keeps the original timestamp.
    func handleSleep() {
        guard sleptAt == nil else { return }

        sleptAt = countdown.now
    }

    /// A transition that came due but never fired, or `nil` while the timer is healthy.
    ///
    /// Keyed to the symptom — a deadline overdue past ``stallGrace`` in a mode that owes a
    /// transition — rather than to any one cause. A stranded `sleptAt` (issue #87) is
    /// covered by this because its deadline keeps aging behind the stuck flag, but so is
    /// any future mechanism that loses an expiry. Whether the flag was set is recorded in
    /// the report as a diagnostic, not required to detect the stall.
    ///
    /// Read when the menu opens, which is both when the user has noticed something is
    /// wrong and proof that the screens are on. A stall detected in the instant before a
    /// real wake notification lands would be a false positive; the cost is one dismissable
    /// warning, which is why this drives a report rather than an automatic recovery.
    var stalledTransition: StalledTransitionReport? {
        guard let overdue = countdown.overdue(at: countdown.now), overdue > Self.stallGrace else {
            return nil
        }

        // Only an actively counting mode owes a transition; the rest have no live deadline
        // to be overdue in the first place.
        guard isRunning else { return nil }

        return StalledTransitionReport(mode: mode, overdueSecs: overdue, wasAsleep: sleptAt != nil)
    }

    /// Clears any stuck sleep flag and lets the overdue transition fire.
    ///
    /// Deliberately *not* ``handleWake()``: that reconciles against `now - sleptAt`, which
    /// is only an absence while the flag is trustworthy. A stalled flag makes it a
    /// fabricated one, and feeding it to ``WakeOutcome`` would discard the work session and
    /// raise a break the user never took. The countdown already ran out, so the transition
    /// it owes is the correct one.
    ///
    /// Runs only from the user pressing reset (issue #89).
    func recoverFromStalledTransition() {
        guard let report = stalledTransition else { return }

        Logger.timer.notice(
            """
            Timer stall reset by the user in mode \(String(describing: report.mode), privacy: .public) \
            after \(report.overdueSecs.formatted(.number.precision(.fractionLength(0))), privacy: .public)s \
            overdue, asleep flag \(report.wasAsleep ? "stuck" : "clear", privacy: .public).
            """
        )

        sleptAt = nil
        handleCountdownExpiryIfNeeded()
    }

    /// Reconciles the timer with the wall-clock time that elapsed while asleep.
    ///
    /// Resting continues on wall-clock and resolves on wake — the remainder resumes, or
    /// the break completes if it elapsed. Work and postponed work defer to
    /// ``WakeOutcome``. A user pause is left untouched.
    func handleWake() {
        guard let sleptAt else { return }

        let away = countdown.now.timeIntervalSince(sleptAt)
        let workRemaining = countdown.remaining(at: sleptAt)
        self.sleptAt = nil

        switch mode {
        case .running, .postponedWork:
            applyWorkWakeOutcome(
                WakeOutcome.resolve(
                    isPostponedWork: mode == .postponedWork,
                    away: away,
                    workRemaining: workRemaining,
                    restDuration: restDurationSecs,
                    savedRestRemaining: savedRestRemaining
                )
            )
        case .resting:
            // The break ran on wall-clock while away: resume the remainder, or resolve it
            // (auto-resume work, or await the user) if it elapsed.
            resolveCountdownAfterWake()
        case .idle, .paused, .awaitingReturn:
            break
        }
    }

    /// Applies the reconciliation decision for a work or postponed-work absence.
    private func applyWorkWakeOutcome(_ outcome: WakeOutcome) {
        switch outcome {
        case .resumeWork:
            resumeCountdown()
        case .startFreshSession:
            // The absence served as the break, so honor the work-start mode and present the
            // break-end window — none is on screen yet, since the user was working.
            finishBreak(presentingOverlay: true)
        case .resumeBreak(let remaining, let refreshingPostpone):
            // A fresh cycle's break (`refreshingPostpone`) means the *work* countdown ran
            // out during the absence: that session completed, just off-screen. A resumed
            // postponed break's work session was already counted when it entered rest.
            if refreshingPostpone {
                statistics.record(.workSessionCompleted)
            }
            beginRest(for: remaining, refreshingPostpone: refreshingPostpone)
        }
    }

    /// After waking during rest, fires a transition the countdown elapsed into while
    /// away, or re-arms the expiry for the time that still remains.
    private func resolveCountdownAfterWake() {
        if timeRemaining <= 0 {
            handleCountdownExpiryIfNeeded()
        } else {
            resumeCountdown()
        }
    }
}
