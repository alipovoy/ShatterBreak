import Foundation
import os

/// Sleep/wake reconciliation for the timer state machine.
///
/// Split out of ``TimerState`` so the state file stays focused. The countdown never
/// freezes on sleep (issue #4); these methods note when the machine slept and, on wake,
/// reconcile against the wall-clock time spent away via the pure ``WakeOutcome``.
extension TimerState {
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

    /// A transition that came due but cannot fire, or `nil` while the timer is healthy.
    ///
    /// Three things must hold at once, and together they mean "a transition is overdue and
    /// blocked" rather than anything about sleep: the asleep flag is set, the countdown has
    /// run out, and the mode is one that owes a transition. A deferral on its own is
    /// routine — every sleep that outlasts the countdown produces one, and ``handleWake()``
    /// resolves it — so the expiry is what separates the bug from normal operation.
    ///
    /// Read when the menu opens, which is both when the user has noticed something is wrong
    /// and proof that the screens are on. A stall detected the instant a real wake lands,
    /// just before its notification arrives, would be a false positive; the cost is one
    /// dismissable warning, which is why this drives a report rather than an automatic
    /// recovery (issue #89).
    var stalledTransition: StalledTransitionReport? {
        guard let sleptAt else { return nil }
        guard countdown.remaining(at: countdown.now) <= 0 else { return nil }

        switch mode {
        case .running, .resting, .postponedWork:
            return StalledTransitionReport(
                mode: mode,
                asleepSecs: countdown.now.timeIntervalSince(sleptAt)
            )
        case .idle, .paused, .awaitingReturn:
            return nil
        }
    }

    /// Clears the stuck flag and lets the overdue transition fire.
    ///
    /// Deliberately *not* ``handleWake()``: that reconciles against `now - sleptAt`, which
    /// is only an absence while the flag is trustworthy. A stalled flag makes it a
    /// fabricated one, and feeding it to ``WakeOutcome`` would discard the work session and
    /// raise a break the user never took. Cancelling the deferral is the whole recovery —
    /// the countdown already ran out, so the transition it owes is the correct one.
    ///
    /// Runs only from the user pressing reset. That consent is what makes it safe where an
    /// automatic self-heal would not be (issue #89).
    func recoverFromStalledTransition() {
        guard let report = stalledTransition else { return }

        Logger.timer.notice(
            """
            Timer stall reset by the user in mode \(String(describing: report.mode), privacy: .public) \
            after \(report.asleepSecs.formatted(.number.precision(.fractionLength(0))), privacy: .public)s \
            with the asleep flag stuck.
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
