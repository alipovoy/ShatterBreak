import Foundation

/// The timer state machine, as pure functions over ``TimerPlan``.
///
/// - **Idempotent**: advancing twice to the same instant owes no second set of effects, so a
///   doubled timer or a wake alongside a heartbeat is harmless.
/// - **Total**: every state has an answer for every instant, so a lost callback costs one
///   tick, not the session.
enum TimerReducer {
    // MARK: - Reconciliation

    /// Brings `plan` up to date, crossing at most one boundary.
    ///
    /// One, deliberately: looping would replay a three-hour sleep as four cycles. An absence
    /// is one event.
    ///
    /// - Parameter override: for callers that measured the absence themselves.
    static func advance(
        _ plan: TimerPlan,
        to instant: TimerInstant,
        prefs: TimerPreferences,
        creditingAbsence override: TimeInterval? = nil
    ) -> (TimerPlan, [TimerEffect]) {
        var plan = plan
        let absence = max(override ?? 0, measuredAbsence(plan, at: instant))
        let unattendedCycle = plan.ranUnattended
        plan.lastSeen = instant

        // A user pause outranks any absence: coming back from lunch does not un-freeze it.
        guard plan.pausedAt == nil else { return (plan, []) }

        switch plan.phase {
        case .idle, .awaitingReturn:
            return (plan, [])

        case .work, .postponedWork:
            // Before the boundary check: a long enough absence settles the cycle whether or
            // not the countdown ran out while the user was away.
            if absence > 0, absence >= prefs.awayResetThreshold {
                return finishBreak(plan.spendingAbsence(at: instant), at: instant, prefs: prefs, presenting: true)
            }
            guard plan.rawRemaining(at: instant.date) <= 0 else { return (plan, []) }
            return untallied(
                crossWorkBoundary(plan.spendingAbsence(at: instant), at: instant, prefs: prefs, absence: absence),
                if: unattendedCycle
            )

        case .rest:
            // Time away *is* break taken, so sleep never pauses a break.
            guard plan.rawRemaining(at: instant.date) <= 0 else { return (plan, []) }
            let (next, effects) = finishBreak(
                plan.spendingAbsence(at: instant),
                at: instant,
                prefs: prefs,
                presenting: false
            )
            return untallied((next, [.record(.breakCompleted)] + effects), if: unattendedCycle)
        }
    }

    /// Drops the statistics of a crossing made in an empty room, matching the away-reset
    /// route above, which records nothing at all.
    ///
    /// Only the tally: the transition and its overlay still happen, since a lost wake must
    /// never leave the timer parked.
    private static func untallied(
        _ result: (TimerPlan, [TimerEffect]),
        if unattended: Bool
    ) -> (TimerPlan, [TimerEffect]) {
        guard unattended else { return result }
        return (result.0, result.1.filter { if case .record = $0 { false } else { true } })
    }

    /// Time away, from two independent signals: clock divergence, which needs nothing
    /// delivered, and the sleep notification, which covers a dark display on a running
    /// machine. The second is an improvement, never a requirement.
    static func measuredAbsence(_ plan: TimerPlan, at instant: TimerInstant) -> TimeInterval {
        let wallGap = instant.date.timeIntervalSince(plan.lastSeen.date)
        let awakeGap = instant.awakeUptime - plan.lastSeen.awakeUptime
        let slept = max(0, wallGap - awakeGap)
        // From wherever this absence was last credited, so a still-unattended machine is not
        // told the same thing twice. The credit point narrows an absence already in flight;
        // alone it is no evidence of one.
        let noted = plan.unattendedSince.map { start in
            max(0, instant.date.timeIntervalSince(max(start, plan.absenceCreditedAt ?? start)))
        } ?? 0
        return max(slept, noted)
    }

    // MARK: - Actions

    /// Whether `action` reconciles itself, and so must *not* be handed a reconciled plan:
    /// only `observedWake`, whose absence is measured from state reconciling would retire.
    static func reconcilesInternally(_ action: TimerAction) -> Bool {
        action == .observedWake
    }

    /// Callers reconcile first, so `plan` is current.
    static func apply(
        _ action: TimerAction,
        to plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        // A user action is proof of presence, whatever the last notification claimed —
        // except for the two actions whose subject it is.
        var plan = plan
        if action != .observedSleep && action != .observedWake {
            plan.unattendedSince = nil
            plan.absenceCreditedAt = nil
        }

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
            // Declining a break's last seconds still took the break. From `awaitingReturn`
            // this is the routine manual resume and counts nothing.
            let taken: [TimerEffect] = plan.phase == .rest && plan.pausedAt == nil
                ? [.record(.breakCompleted), .record(.earlyReturn)]
                : []
            let (next, effects) = startWork(plan, at: instant, prefs: prefs)
            return (next, taken + effects)
        case .observedSleep:
            guard plan.unattendedSince == nil else { return (plan, []) }
            plan.unattendedSince = instant.date
            return (plan, [])
        case .observedWake:
            return returned(plan, at: instant, prefs: prefs)
        }
    }

    /// Measured here rather than by ``measuredAbsence(_:at:)``, which sees only the
    /// uncredited remainder: a session that restarted in the dark is not the fresh one the
    /// user is owed on returning.
    private static func returned(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences
    ) -> (TimerPlan, [TimerEffect]) {
        var plan = plan
        let absence = plan.unattendedSince.map { max(0, instant.date.timeIntervalSince($0)) }
        // Before reconciling, so a session this starts counts as attended and settles the
        // consent its break will need.
        plan.unattendedSince = nil
        plan.absenceCreditedAt = nil
        return advance(plan, to: instant, prefs: prefs, creditingAbsence: absence)
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
            // Skipping rest abandons it rather than freezing it, so no break is counted.
            return startWork(plan, at: instant, prefs: prefs)
        case .idle, .awaitingReturn:
            return (plan, [])
        }
    }

    private static func resume(_ plan: TimerPlan, at instant: TimerInstant) -> TimerPlan {
        guard let pausedAt = plan.pausedAt else { return plan }

        var plan = plan
        // Sliding the start preserves the remainder exactly without storing it.
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

    /// The one start every route funnels through, so a session behaves identically whatever
    /// preceded it.
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
        // Settling consent can raise a system dialog, and sessions restarting in an empty
        // room would stack them up. The session the user returns to settles it.
        if plan.unattendedSince == nil {
            effects.append(.prepareCapturePermissions)
        }

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

    /// The break is credited with the *whole* absence, not just the part past the boundary.
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

        // Only reachable when a postpone left less than a full break and the absence covered
        // it; a regular break is guarded by the away-reset rule above.
        guard breakRemaining > 0 else {
            return finishBreak(plan, at: instant, prefs: prefs, presenting: true)
        }

        // A resumed postponed break was already counted when it first entered rest.
        let effects: [TimerEffect] = resumingPostponedBreak ? [] : [.record(.workSessionCompleted)]
        let next = beginRest(
            plan,
            for: breakRemaining,
            at: instant,
            refreshingPostpone: resumingPostponedBreak == false
        )
        return (next, effects + [.showOverlay(.animated)])
    }

    /// `refreshingPostpone` restores postpone for a new cycle's break; a resumed remainder
    /// keeps it spent for the rest of the cycle.
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

    /// `presenting` raises the break-end window for the route where nothing is on screen yet.
    /// Always `.settled`: the break elapsed silently, so a shake and chime on return would
    /// announce something already over.
    private static func finishBreak(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences,
        presenting: Bool
    ) -> (TimerPlan, [TimerEffect]) {
        guard prefs.autoStartWork else {
            // An overlay held back from a dark display still carries the shake and chime of a
            // break that has now ended.
            return (awaitReturn(plan, at: instant), presenting ? [.showOverlay(.settled)] : [.settleHeldOverlay])
        }
        return startWork(plan, at: instant, prefs: prefs)
    }

    private static func awaitReturn(_ plan: TimerPlan, at instant: TimerInstant) -> TimerPlan {
        var plan = plan
        plan.phase = .awaitingReturn
        plan.startedAt = instant.date
        plan.duration = 0
        plan.pausedAt = nil
        plan.savedRestRemaining = nil
        plan.unattendedSince = nil
        plan.absenceCreditedAt = nil
        plan.lastSeen = instant
        plan.intervalID += 1
        return plan
    }
}

private extension TimerPlan {
    /// Without this a still-unattended machine re-resolves the same absence at every
    /// heartbeat and idempotency does not hold. `unattendedSince` stays: the user's actual
    /// return is owed a decision about the whole absence.
    func spendingAbsence(at instant: TimerInstant) -> TimerPlan {
        guard unattendedSince != nil else { return self }
        var plan = self
        plan.absenceCreditedAt = instant.date
        return plan
    }
}
