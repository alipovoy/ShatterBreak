import Foundation

/// How a work or postponed-work countdown should resolve after the timer wakes, given
/// the wall-clock time spent asleep.
///
/// Pulled out as a pure value (like ``OverlayPhaseAction``) so the reconciliation rule —
/// refined across issues #69 and #72 — can be unit-tested without driving the whole
/// ``TimerState`` machine.
enum WakeOutcome: Equatable {
    /// Continue the interrupted work countdown with the time that still remains.
    case resumeWork
    /// Begin a fresh work session: the absence itself served as the break.
    case startFreshSession
    /// Re-enter the break with `remaining` on the clock. `refreshingPostpone` restores
    /// postpone availability for a brand-new cycle's break.
    case resumeBreak(remaining: TimeInterval, refreshingPostpone: Bool)

    /// Resolves the outcome for an absence of `away` seconds.
    ///
    /// With `W` the work time remaining when sleep began and `R` the break duration:
    /// `away >= R` starts fresh (the absence is a full break); `away <= W` resumes work;
    /// otherwise the absence spilled into the break, which resumes crediting the *whole*
    /// time away as rest (`break - away`). A remainder the absence fully covered —
    /// possible when a postpone left less than a full break — also starts fresh.
    ///
    /// - Parameters:
    ///   - isPostponedWork: whether the sleeping countdown was a postponed-work period.
    ///   - away: wall-clock seconds spent asleep.
    ///   - workRemaining: work seconds left when sleep began (`W`).
    ///   - restDuration: the full break duration (`R`), used as the reset threshold.
    ///   - savedRestRemaining: the postponed break's remainder, when a postpone is in flight.
    static func resolve(
        isPostponedWork: Bool,
        away: TimeInterval,
        workRemaining: TimeInterval,
        restDuration: TimeInterval,
        savedRestRemaining: TimeInterval?
    ) -> WakeOutcome {
        if away >= restDuration {
            return .startFreshSession
        }

        if away <= workRemaining {
            return .resumeWork
        }

        let breakDuration = isPostponedWork ? (savedRestRemaining ?? restDuration) : restDuration
        let breakRemaining = breakDuration - away

        guard breakRemaining > 0 else {
            return .startFreshSession
        }

        return .resumeBreak(remaining: breakRemaining, refreshingPostpone: !isPostponedWork)
    }
}
