import Foundation

/// The complete mutable state of the timer, as one value.
///
/// Everything a countdown *is* lives here; everything a countdown *shows* is derived from
/// this plus the current moment. There is deliberately no `deadline`, no
/// `frozenRemaining`, and no "is asleep" flag gating transitions: those were separate
/// pieces of truth that could disagree, and every one of them did at least once
/// (issues #87, #106, #108).
///
/// In memory only. A relaunch or crash starts fresh, honouring the auto-start-on-launch
/// preference (#66); statistics keep their own store and are unaffected.
struct TimerPlan: Equatable, Sendable {
    /// What the timer is doing. Note that pausing is *not* a phase: a paused work session
    /// is still `work`, with ``pausedAt`` set. That removes the "which mode do I restore?"
    /// bookkeeping a `paused` phase forces on every caller.
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

    /// Identifies the interval currently on the clock, bumped on every phase entry.
    ///
    /// Two consecutive work sessions are identical in every other field, so this is what a
    /// view keys its refresh loop on. Keying on the phase alone left the menu bar rendering
    /// a finished session after work auto-resumed (issue #108).
    var intervalID: Int

    /// Break time owed back after a postpone, or `nil` when no postpone is in flight.
    var savedRestRemaining: TimeInterval?
    /// Postpone is offered once per work→break cycle; a resumed postpone remainder keeps
    /// it spent, a brand-new cycle's break restores it.
    var postponeUsedThisCycle: Bool

    /// When the machine last told us it was going unattended (system or display sleep).
    ///
    /// Only ever an *input* to measuring how long the user was away — never a gate on
    /// transitions. That distinction is the whole of issue #87: the old asleep flag blocked
    /// every transition behind it, so a wake notification that never arrived stalled the
    /// timer permanently. Here a stale value at worst credits an absence that
    /// ``TimerReducer/measuredAbsence(_:at:)`` would have measured anyway.
    var unattendedSince: Date?

    /// How much of ``unattendedSince`` has already been resolved into a transition.
    ///
    /// A display that sleeps while the machine keeps running leaves the notification as the
    /// only evidence, and it keeps growing for as long as nobody comes back. Without this,
    /// the same absence would be credited again at every heartbeat past the threshold,
    /// restarting the work session over and over. Kept separate from ``unattendedSince``
    /// rather than advancing it, because the moment the user actually returns they are owed
    /// a decision about the *whole* absence, not the sliver since it was last credited.
    var absenceCreditedAt: Date?

    /// The moment the reducer last ran. The gap to the next one, compared against the
    /// awake-only clock, is what proves the machine slept — no notification required.
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

    /// Whether a countdown is actually ticking: a live phase that is not paused.
    var isCountingDown: Bool {
        guard pausedAt == nil else { return false }
        switch phase {
        case .work, .rest, .postponedWork: return true
        case .idle, .awaitingReturn: return false
        }
    }

    /// Time left on the clock, clamped at zero — what the user sees.
    func remaining(at now: Date) -> TimeInterval {
        max(0, rawRemaining(at: now))
    }

    /// Time left without the clamp, so the reducer can tell "just expired" from "expired a
    /// while ago" and, negatively, how far past the boundary `now` is.
    func rawRemaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .awaitingReturn:
            return 0
        case .work, .rest, .postponedWork:
            return duration - (pausedAt ?? now).timeIntervalSince(startedAt)
        }
    }
}

/// A moment, measured on both clocks the timer needs.
///
/// The pair is the point. `date` moves while the machine sleeps; `awakeUptime` does not
/// (it is `ProcessInfo.systemUptime`, which excludes sleep). The difference between two
/// instants' gaps is therefore how long the machine was asleep — measured, not inferred
/// from a notification that may never arrive.
struct TimerInstant: Equatable, Sendable {
    var date: Date
    /// Seconds the machine has been awake. Advances only while the machine is running.
    var awakeUptime: TimeInterval
}
