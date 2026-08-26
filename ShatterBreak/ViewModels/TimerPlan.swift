import Foundation

/// The complete state of the timer, as one value; everything shown is derived from this
/// plus the current moment.
///
/// Deliberately no `deadline`, no `frozenRemaining` and no "is asleep" flag: separate
/// pieces of truth that could disagree, and each did at least once (#87, #106, #108).
///
/// In memory only — a relaunch starts fresh, honouring auto-start-on-launch (#66).
struct TimerPlan: Equatable, Sendable {
    /// What the timer is doing. Pausing is *not* a phase — a paused work session is still
    /// `work` with ``pausedAt`` set — which removes the "which mode do I restore?"
    /// bookkeeping it would force on callers.
    enum Phase: Equatable, Sendable {
        case idle
        case work
        case rest
        case postponedWork
        /// Manual work-start mode: the break is over and the user has not come back yet.
        case awaitingReturn
    }

    var phase: Phase
    /// Wall-clock moment this phase began. With ``duration`` this is the whole countdown.
    var startedAt: Date
    /// Nominal length of this phase. Zero for ``Phase/idle`` and ``Phase/awaitingReturn``,
    /// which do not count down.
    var duration: TimeInterval
    /// Set while the user has paused. The frozen remainder is derived from it, not stored.
    var pausedAt: Date?

    /// Bumped on every phase entry, for views to key their refresh loop on. Two consecutive
    /// work sessions are identical in every other field, and keying on phase alone left the
    /// menu bar rendering a finished session after work auto-resumed (#108).
    var intervalID: Int

    /// Break time owed back after a postpone, or `nil` when no postpone is in flight.
    var savedRestRemaining: TimeInterval?
    /// Postpone is offered once per work→break cycle; a resumed postpone remainder keeps
    /// it spent, a brand-new cycle's break restores it.
    var postponeUsedThisCycle: Bool

    /// When the machine last reported going unattended (system or display sleep).
    ///
    /// An *input* to measuring the absence, never a gate on transitions — that distinction
    /// is the whole of #87, where the old asleep flag stalled the timer permanently when a
    /// wake notification never arrived.
    ///
    /// It is not free of that failure, only downgraded. This is the sole evidence for a
    /// display asleep on a running machine, where the two clocks show nothing, so a value
    /// left standing — a lost wake, and a user who returns without touching the app —
    /// restarts the work session once per ``TimerPreferences/awayResetThreshold`` for as
    /// long as it stands. A stalled timer became a silently repeating one. Any user action
    /// clears it (`TimerReducer.apply`), which is what usually ends it.
    var unattendedSince: Date?

    /// How much of ``unattendedSince`` has already been resolved into a transition, without
    /// which the same absence would be credited at every heartbeat past the threshold.
    ///
    /// Separate from ``unattendedSince`` rather than advancing it: the user's actual return
    /// is owed a decision about the *whole* absence, not the sliver since the last credit.
    var absenceCreditedAt: Date?

    /// The moment the reducer last ran. The gap to the next one, against the awake-only
    /// clock, is what proves the machine slept — no notification required.
    var lastSeen: TimerInstant

    static func idle(at instant: TimerInstant) -> TimerPlan {
        TimerPlan(
            phase: .idle,
            startedAt: instant.date,
            duration: 0,
            pausedAt: nil,
            intervalID: 0,
            savedRestRemaining: nil,
            postponeUsedThisCycle: false,
            unattendedSince: nil,
            absenceCreditedAt: nil,
            lastSeen: instant
        )
    }

    var isCountingDown: Bool {
        guard pausedAt == nil else { return false }
        switch phase {
        case .work, .rest, .postponedWork: return true
        case .idle, .awaitingReturn: return false
        }
    }

    /// What the user sees: time left, clamped at zero.
    func remaining(at now: Date) -> TimeInterval {
        max(0, rawRemaining(at: now))
    }

    /// Unclamped, so the reducer can tell "just expired" from "expired long ago".
    func rawRemaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .awaitingReturn:
            return 0
        case .work, .rest, .postponedWork:
            return duration - (pausedAt ?? now).timeIntervalSince(startedAt)
        }
    }
}

/// A moment on both clocks the timer needs.
///
/// The pair is the point: `date` moves while the machine sleeps, `awakeUptime` does not, so
/// the difference between two instants' gaps is how long it slept — measured, not inferred
/// from a notification that may never arrive.
struct TimerInstant: Equatable, Sendable {
    var date: Date
    /// `ProcessInfo.systemUptime`: advances only while the machine is running.
    var awakeUptime: TimeInterval
}
