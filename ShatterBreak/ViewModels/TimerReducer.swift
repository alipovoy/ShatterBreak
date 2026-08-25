import Foundation

/// The entire timer state machine, as pure functions over ``TimerPlan``.
///
/// No clock reads, no I/O, no actor. Callers supply the moment; the reducer returns the
/// next plan and the effects the world owes. Two properties make it worth the shape:
///
/// - **Idempotent.** Running ``advance(_:to:prefs:)`` twice for the same instant produces
///   the same plan and no second set of effects. That is what makes a timer that fires
///   twice, or a wake notification that arrives alongside a heartbeat, harmless.
/// - **Total.** Every reachable state has a defined answer for every instant, so a lost
///   callback costs one tick instead of the session. The old design mutated state at the
///   instant an event arrived, which made a dropped event permanent (#87, #106, #108).
enum TimerReducer {
    // MARK: - Reconciliation

    /// Brings `plan` up to date with `instant`, crossing at most one boundary.
    ///
    /// At most one, deliberately: the obvious `while remaining <= 0 { cross() }` would
    /// replay a three-hour sleep as four work→break cycles and record four completed
    /// sessions. An absence is resolved as a single event instead, which is also what the
    /// user experienced — one time away, not four cycles.
    static func advance(
        _ plan: TimerPlan,
        to instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        var plan = plan
        let absence = measuredAbsence(plan, at: instant)
        plan.lastSeen = instant

        // A user pause is the one thing an absence must not disturb: the timer is frozen
        // because the user froze it, and coming back from lunch does not un-freeze it.
        guard plan.pausedAt == nil else { return (plan, []) }

        switch plan.phase {
        case .idle, .awaitingReturn:
            return (plan, [])

        case .work, .postponedWork:
            // Resolved before the boundary check, because a long enough absence settles the
            // cycle whether or not the work countdown ran out while the user was away (#69).
            if absence > 0, absence >= prefs.awayResetThreshold {
                return finishBreak(plan.spendingAbsence(at: instant), at: instant, prefs: prefs, presenting: true)
            }
            guard plan.rawRemaining(at: instant.date) <= 0 else { return (plan, []) }
            return crossWorkBoundary(plan.spendingAbsence(at: instant), at: instant, prefs: prefs, absence: absence)

        case .rest:
            // A break runs on the wall clock and needs no absence policy: time away *is*
            // break taken, which is why the countdown never pauses on sleep (#4).
            guard plan.rawRemaining(at: instant.date) <= 0 else { return (plan, []) }
            let (next, effects) = finishBreak(
                plan.spendingAbsence(at: instant),
                at: instant,
                prefs: prefs,
                presenting: false
            )
            return (next, [.record(.breakCompleted)] + effects)
        }
    }

    /// How long the user has been away, from the two independent kinds of evidence.
    ///
    /// The measured one is authoritative and needs nothing to be delivered: wall-clock time
    /// that passed while the awake-only clock stood still is time the machine spent asleep.
    /// The notification timestamp covers what that cannot see — a display asleep while the
    /// machine keeps running — and is a pure improvement, never a requirement.
    static func measuredAbsence(_ plan: TimerPlan, at instant: TimerInstant) -> TimeInterval {
        let wallGap = instant.date.timeIntervalSince(plan.lastSeen.date)
        let awakeGap = instant.awakeUptime - plan.lastSeen.awakeUptime
        let slept = max(0, wallGap - awakeGap)
        let noted = plan.unattendedSince.map { max(0, instant.date.timeIntervalSince($0)) } ?? 0
        return max(slept, noted)
    }

    // MARK: - Actions

    /// Applies a user or system action. Callers reconcile first, so `plan` is current.
    static func apply(
        _ action: TimerAction,
        to plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        switch action {
        case .start:
            return startWork(plan, at: instant, prefs: prefs)
        case .pause:
            return pause(plan, at: instant, prefs: prefs)
        case .resume:
            return (resume(plan, at: instant), [])
        case .stop:
            var next = TimerPlan.idle(at: instant)
            next.intervalID = plan.intervalID + 1
            return (next, [.dismissOverlay])
        case .postpone:
            return postpone(plan, at: instant, prefs: prefs)
        case .returnToWork:
            // Tapped inside the break's closing early-return window: the rest happened, the
            // user just declines its last seconds, so the break counts and the early return
            // is tallied so a pattern of cutting breaks short stays visible. From
            // `awaitingReturn` it is the routine manual resume and counts nothing.
            let taken: [TimerEffect] = plan.phase == .rest && plan.pausedAt == nil
                ? [.record(.breakCompleted), .record(.earlyReturn)]
                : []
            let (next, effects) = startWork(plan, at: instant, prefs: prefs)
            return (next, taken + effects)
        case .observedSleep:
            guard plan.unattendedSince == nil else { return (plan, []) }
            var plan = plan
            plan.unattendedSince = instant.date
            return (plan, [])
        case .observedWake:
            // Reconcile before retiring the timestamp: it is the input the absence is
            // measured from, and clearing it first would throw away the evidence.
            var (plan, effects) = advance(plan, to: instant, prefs: prefs)
            plan.unattendedSince = nil
            return (plan, effects)
        }
    }

    private static func pause(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        guard plan.pausedAt == nil else { return (plan, []) }

        switch plan.phase {
        case .work, .postponedWork:
            var plan = plan
            plan.pausedAt = instant.date
            plan.lastSeen = instant
            return (plan, [])
        case .rest:
            // "Skip rest": the break is abandoned rather than frozen, so it counts as no
            // break taken and work begins immediately.
            return startWork(plan, at: instant, prefs: prefs)
        case .idle, .awaitingReturn:
            return (plan, [])
        }
    }

    private static func resume(_ plan: TimerPlan, at instant: TimerInstant) -> TimerPlan {
        guard let pausedAt = plan.pausedAt else { return plan }

        var plan = plan
        // Slide the start forward by the frozen span, which preserves the remainder exactly
        // without ever storing it.
        plan.startedAt = plan.startedAt.addingTimeInterval(instant.date.timeIntervalSince(pausedAt))
        plan.pausedAt = nil
        plan.lastSeen = instant
        plan.intervalID += 1
        return plan
    }

    private static func postpone(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        guard plan.phase == .rest, plan.pausedAt == nil, plan.postponeUsedThisCycle == false else {
            return (plan, [])
        }

        var plan = plan
        plan.savedRestRemaining = plan.remaining(at: instant.date)
        plan.postponeUsedThisCycle = true
        plan.phase = .postponedWork
        plan.startedAt = instant.date
        plan.duration = max(0, prefs.postponeDuration)
        plan.lastSeen = instant
        plan.intervalID += 1
        return (plan, [.record(.postponed), .dismissOverlay])
    }

    // MARK: - Transitions

    /// Begins a work session. Also the "start" every other route funnels through, so a
    /// fresh session behaves identically no matter what preceded it.
    private static func startWork(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        var effects: [TimerEffect] = []
        // Only the stop→start boundary begins a fresh tally; a cycle rolling over does not.
        if plan.phase == .idle, plan.pausedAt == nil {
            effects.append(.resetStatisticsForNewSession)
        }
        if plan.phase == .rest || plan.phase == .awaitingReturn {
            effects.append(.dismissOverlay)
        }
        effects.append(.prepareCapturePermissions)

        var plan = plan
        plan.phase = .work
        plan.startedAt = instant.date
        plan.duration = max(0, prefs.workDuration)
        plan.pausedAt = nil
        plan.lastSeen = instant
        plan.intervalID += 1
        // A new work session owes nothing to the break that did not happen.
        plan.savedRestRemaining = nil
        return (plan, effects)
    }

    /// The work (or postponed-work) countdown reached zero.
    ///
    /// The break that follows is credited with the *whole* absence, not just the part that
    /// fell past the boundary: the user was away for all of it, and the break they owe
    /// themselves is that much shorter (#72). With no absence this is the ordinary
    /// transition and the break gets its full duration.
    private static func crossWorkBoundary(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences,
        absence: TimeInterval
    ) -> (TimerPlan, [TimerEffect]) {
        let resumingPostponedBreak = plan.phase == .postponedWork
        let breakDuration = resumingPostponedBreak
            ? (plan.savedRestRemaining ?? prefs.restDuration)
            : prefs.restDuration
        let breakRemaining = breakDuration - absence

        // Reachable only when a postpone left less than a full break and the absence
        // covered all of it; a regular break is guarded by the away-reset rule above.
        guard breakRemaining > 0 else {
            return finishBreak(plan, at: instant, prefs: prefs, presenting: true)
        }

        // A brand-new cycle's break means the *work* session completed, just possibly
        // off-screen. A resumed postponed break was already counted when it first entered
        // rest, so counting again would inflate the tally.
        let effects: [TimerEffect] = resumingPostponedBreak ? [] : [.record(.workSessionCompleted)]
        let next = beginRest(
            plan,
            for: breakRemaining,
            at: instant,
            refreshingPostpone: resumingPostponedBreak == false
        )
        return (next, effects + [.showOverlay(.animated)])
    }

    /// Enters the break with `duration` on the clock.
    ///
    /// `refreshingPostpone` restores postpone for a brand-new cycle's break; a resumed
    /// postpone remainder keeps it spent for the rest of the cycle.
    private static func beginRest(
        _ plan: TimerPlan,
        for duration: TimeInterval,
        at instant: TimerInstant,
        refreshingPostpone: Bool
    ) -> TimerPlan {
        var plan = plan
        plan.phase = .rest
        plan.startedAt = instant.date
        plan.duration = max(0, duration)
        plan.pausedAt = nil
        plan.savedRestRemaining = nil
        plan.intervalID += 1
        if refreshingPostpone {
            plan.postponeUsedThisCycle = false
        }
        return plan
    }

    /// The break is over, however it was served — counted down on screen, or replaced by an
    /// absence long enough to be one.
    ///
    /// `presenting` puts the break-end window up for the route where no overlay is on
    /// screen yet because the user was working when they walked away. That window is always
    /// `.settled`: the break already elapsed silently, so a shake and a chime on return
    /// would be announcing something that is already over (#76, #94).
    private static func finishBreak(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences,
        presenting: Bool
    ) -> (TimerPlan, [TimerEffect]) {
        guard prefs.autoStartWork else {
            return (awaitReturn(plan, at: instant), presenting ? [.showOverlay(.settled)] : [])
        }
        return startWork(plan, at: instant, prefs: prefs)
    }

    /// Manual work-start mode: park until the user says they are back.
    private static func awaitReturn(_ plan: TimerPlan, at instant: TimerInstant) -> TimerPlan {
        var plan = plan
        plan.phase = .awaitingReturn
        plan.startedAt = instant.date
        plan.duration = 0
        plan.pausedAt = nil
        plan.savedRestRemaining = nil
        plan.unattendedSince = nil
        plan.lastSeen = instant
        plan.intervalID += 1
        return plan
    }
}

private extension TimerPlan {
    /// Marks the absence measured so far as accounted for.
    ///
    /// Without this, a machine that is still unattended would re-resolve the same absence
    /// at every heartbeat, resetting the work session over and over — and idempotency,
    /// which everything else here rests on, would not hold.
    func spendingAbsence(at instant: TimerInstant) -> TimerPlan {
        guard unattendedSince != nil else { return self }
        var plan = self
        plan.unattendedSince = instant.date
        return plan
    }
}
