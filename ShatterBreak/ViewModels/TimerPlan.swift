import Foundation

/// The whole timer as one value; everything shown derives from it and the current moment.
///
/// No `deadline`, `frozenRemaining` or "is asleep" flag: separate truths that could
/// disagree, and each did. In memory only, so a relaunch starts fresh.
struct TimerPlan: Equatable, Sendable {
    /// Pausing is not a phase: a paused work session is still `work`, with ``pausedAt`` set.
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

    /// Bumped on every phase entry: two consecutive work sessions differ in nothing else.
    var intervalID: Int

    /// Break time owed back after a postpone.
    var savedRestRemaining: TimeInterval?
    /// Postpone is offered once per work→break cycle; a resumed remainder keeps it spent, a
    /// new cycle's break restores it.
    var postponeUsedThisCycle: Bool

    /// The session credit is spent this cycle (issue #71). A flag, not a phase: a counted
    /// work session is still work.
    var sessionCredited: Bool

    /// When the machine last reported going unattended. An input to measuring the absence,
    /// never a gate: a gate stalled the timer for good when a wake never arrived. Any user
    /// action clears it.
    var unattendedSince: Date?

    /// How much of the absence is already resolved, so it is not settled again at every
    /// heartbeat. Separate, because the user's return is owed a decision about all of it.
    var absenceResolvedAt: Date?

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
            sessionCredited: false,
            unattendedSince: nil,
            absenceResolvedAt: nil,
            lastSeen: instant
        )
    }

    /// A plan already in a phase, for previews and the effect sample.
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

/// A moment on both clocks: `date` moves while the machine sleeps and `awakeUptime` does not,
/// so two instants measure a sleep without relying on a notification.
struct TimerInstant: Equatable, Sendable {
    var date: Date
    /// `ProcessInfo.systemUptime`: advances only while the machine is running.
    var awakeUptime: TimeInterval

    static var now: TimerInstant {
        TimerInstant(date: .now, awakeUptime: ProcessInfo.processInfo.systemUptime)
    }
}
