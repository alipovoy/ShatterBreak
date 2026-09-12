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
                return untallied(
                    settleByAbsence(plan.resolvingAbsence(at: instant), at: instant, prefs: prefs, absence: absence),
                    if: unattendedCycle
                )
            }

            // One `remaining` for both decisions below, which is the whole of the difference
            // between them: the credit point, then the boundary a lead later.
            let remaining = plan.rawRemaining(at: instant.date)
            var tally: [TimerEffect] = []
            // Counting a session needs the user here, and an absence shorter than the
            // away-reset is no evidence of that. Withholding costs nothing: the credit stays
            // unspent, so a return takes it and the boundary below still judges it.
            if plan.phase == .work,
               plan.sessionCredited == false,
               plan.unattendedSince == nil,
               // Never at the instant work begins, which a lead as long as the session is.
               instant.date > plan.startedAt,
               remaining <= creditLead(prefs) {
                plan.sessionCredited = true
                tally = [.record(.workSessionCompleted)]
                // No `resolvingAbsence`: narrowing an absence here would stop it ever reaching
                // the away-reset.
            }

            guard remaining <= 0 else { return (plan, tally) }
            let (next, effects) = crossWorkBoundary(
                plan.resolvingAbsence(at: instant),
                at: instant,
                prefs: prefs,
                absence: absence
            )
            return untallied((next, tally + effects), if: unattendedCycle)

        case .rest:
            // Time away *is* break taken, so sleep never pauses a break.
            guard plan.rawRemaining(at: instant.date) <= 0 else { return (plan, []) }
            let (next, effects) = finishBreak(
                plan.resolvingAbsence(at: instant),
                at: instant,
                prefs: prefs,
                presenting: false
            )
            return untallied((next, [.record(.breakCompleted)] + effects), if: unattendedCycle)
        }
    }

    /// Drops the statistics of a crossing made in an empty room, matching the away-reset
    /// route above, which counts nothing it cannot show someone was here for.
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
        // From wherever this absence was last resolved, so a still-unattended machine is not
        // told the same thing twice. A resolution narrows an absence already in flight;
        // alone it is no evidence of one.
        let noted = plan.unattendedSince.map { start in
            max(0, instant.date.timeIntervalSince(max(start, plan.absenceResolvedAt ?? start)))
        } ?? 0
        return max(slept, noted)
    }

    /// A negative preference can only mean what zero means: count at the boundary.
    static func creditLead(_ prefs: TimerPreferences) -> TimeInterval {
        max(0, prefs.sessionLead)
    }

    /// When the reducer next has something to do, for callers arming a timer: the credit
    /// point while a work session is still short of it, the end of the countdown otherwise.
    ///
    /// The heartbeat behind the boundary timer runs every 30 seconds — far too coarse to land
    /// a lead on, and a lead landing at the boundary instead is a lead that did nothing.
    ///
    /// The credit point is never answered with zero: a session sitting past it uncredited is
    /// waiting for the user, not for the clock, and zero would be rescheduled the moment it
    /// fired for as long as the machine stayed dark.
    static func nextTransition(
        _ plan: TimerPlan,
        at now: Date,
        prefs: TimerPreferences
    ) -> TimeInterval? {
        guard plan.isCountingDown else { return nil }
        let remaining = plan.rawRemaining(at: now)
        let untilCreditPoint = remaining - creditLead(prefs)
        guard plan.phase == .work, plan.sessionCredited == false, untilCreditPoint > 0 else {
            return max(0, remaining)
        }
        return untilCreditPoint
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
            plan.absenceResolvedAt = nil
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
    /// unresolved remainder: a session that restarted in the dark is not the fresh one the
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
        plan.absenceResolvedAt = nil
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
}

private extension TimerPlan {
    /// Without this a still-unattended machine re-resolves the same absence at every
    /// heartbeat and idempotency does not hold. `unattendedSince` stays: the user's actual
    /// return is owed a decision about the whole absence.
    func resolvingAbsence(at instant: TimerInstant) -> TimerPlan {
        guard unattendedSince != nil else { return self }
        var plan = self
        plan.absenceResolvedAt = instant.date
        return plan
    }
}
