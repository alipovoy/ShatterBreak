import Foundation

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
