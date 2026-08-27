import Foundation

/// The whole timer as one value; everything shown derives from this plus the current moment.
///
/// Deliberately no `deadline`, no `frozenRemaining` and no "is asleep" flag: separate truths
/// that could disagree, and each did.
///
/// In memory only, so a relaunch starts fresh and honours auto-start-on-launch.
struct TimerPlan: Equatable, Sendable {
    /// Pausing is deliberately *not* a phase — a paused work session is still `work` with
    /// ``pausedAt`` set — which spares callers "which mode do I restore?" bookkeeping.
    enum Phase: Equatable, Sendable {
        case idle
        case work
        case rest
        case postponedWork
        /// Manual work-start mode: the break is over and the user has not come back yet.
        case awaitingReturn
    }

    var phase: Phase
    var startedAt: Date
    /// Zero for the phases that do not count down.
    var duration: TimeInterval
    /// The frozen remainder is derived from this, not stored.
    var pausedAt: Date?

    /// Bumped on every phase entry, for views to key their refresh loop on. Two consecutive
    /// work sessions are identical in every other field, so keying on phase alone left the
    /// menu bar rendering a finished session after work auto-resumed.
    var intervalID: Int

    /// Break time owed back after a postpone.
    var savedRestRemaining: TimeInterval?
    /// Postpone is offered once per work→break cycle; a resumed remainder keeps it spent, a
    /// new cycle's break restores it.
    var postponeUsedThisCycle: Bool

    /// When the machine last reported going unattended (system or display sleep).
    ///
    /// An *input* to measuring the absence, never a gate on transitions: the old asleep flag
    /// was a gate, and stalled the timer for good when a wake never arrived. A lost wake here
    /// leaves the timer cycling in an empty room instead, which ``ranUnattended`` keeps from
    /// tallying. Any user action clears it.
    var unattendedSince: Date?

    /// How much of ``unattendedSince`` is already resolved into a transition, without which
    /// the same absence is credited at every heartbeat past the threshold.
    ///
    /// Separate from ``unattendedSince`` rather than advancing it: the user's actual return
    /// is owed a decision about the *whole* absence.
    var absenceCreditedAt: Date?

    /// The gap between two of these, against the awake-only clock, is what proves the machine
    /// slept — no notification required.
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

    /// A plan already in a phase, for previews wanting a countdown without driving one to
    /// reach it. Built from ``idle(at:)`` so no field is left describing a cycle that is gone.
    static func starting(
        _ phase: Phase,
        duration: TimeInterval = 300,
        at instant: TimerInstant = .now
    ) -> TimerPlan {
        var plan = TimerPlan.idle(at: instant)
        plan.phase = phase
        // Must not build a plan the reducer never would.
        plan.duration = plan.isCountingDown ? duration : 0
        plan.intervalID = 1
        return plan
    }

    /// Whether this phase ran its whole length with the machine unattended, and so must not
    /// be tallied. The phase begun *before* the machine went dark is real work.
    var ranUnattended: Bool {
        guard let unattendedSince else { return false }
        return startedAt >= unattendedSince
    }

    var isCountingDown: Bool {
        guard pausedAt == nil else { return false }
        switch phase {
        case .work, .rest, .postponedWork: return true
        case .idle, .awaitingReturn: return false
        }
    }

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

/// A moment on both clocks.
///
/// The pair is the point: `date` moves while the machine sleeps, `awakeUptime` does not, so
/// the divergence between two instants measures the sleep rather than inferring it from a
/// notification that may never arrive.
struct TimerInstant: Equatable, Sendable {
    var date: Date
    /// `ProcessInfo.systemUptime`: advances only while the machine is running.
    var awakeUptime: TimeInterval

    /// The one place the process clocks are sampled.
    static var now: TimerInstant {
        TimerInstant(date: .now, awakeUptime: ProcessInfo.processInfo.systemUptime)
    }
}
