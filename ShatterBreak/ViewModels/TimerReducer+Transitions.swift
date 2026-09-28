import Foundation

/// One function per phase entry, so a rule about a phase has one home. Internal only because
/// of the file split; nothing outside ``TimerReducer`` calls them.
extension TimerReducer {
    static func startWork(
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
        plan.savedRestRemaining = nil
        plan.sessionCredited = false
        return (plan, effects)
    }

    /// The break is credited with the whole absence, not just the part past the boundary. A
    /// session still uncredited here passed its credit point unattended, so this is its last
    /// chance.
    static func crossWorkBoundary(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences,
        absence: TimeInterval
    ) -> (TimerPlan, [TimerEffect]) {
        let uncreditedSession: [TimerEffect] = plan.sessionCredited ? [] : [.record(.workSessionCompleted)]
        let resumingPostponedBreak = plan.phase == .postponedWork
        let breakDuration = resumingPostponedBreak
            ? (plan.savedRestRemaining ?? prefs.restDuration)
            : prefs.restDuration
        let breakRemaining = breakDuration - absence

        // Only reachable when a postpone left less than a full break and the absence covered
        // it; a regular break is guarded by the away-reset rule in `advance`.
        guard breakRemaining > 0 else {
            return settleByAbsence(plan, at: instant, prefs: prefs, absence: absence)
        }

        // Spent either way: a postponed stint returning here must not count a second time.
        var plan = plan
        plan.sessionCredited = true
        let next = beginRest(
            plan,
            for: breakRemaining,
            at: instant,
            refreshingPostpone: resumingPostponedBreak == false
        )
        return (next, uncreditedSession + [.showOverlay(.animated)])
    }

    /// `refreshingPostpone` restores postpone for a new cycle's break; a resumed remainder
    /// keeps it spent for the rest of the cycle.
    static func beginRest(
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

    /// `presenting` raises the break-end window where nothing is on screen yet, settled: the
    /// break is already over.
    static func finishBreak(
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

    static func awaitReturn(_ plan: TimerPlan, at instant: TimerInstant) -> TimerPlan {
        var plan = plan
        plan.phase = .awaitingReturn
        plan.startedAt = instant.date
        plan.duration = 0
        plan.pausedAt = nil
        plan.savedRestRemaining = nil
        plan.unattendedSince = nil
        plan.absenceResolvedAt = nil
        plan.lastSeen = instant
        plan.intervalID += 1
        return plan
    }

    /// A break the user's absence stood in for (issue #111).
    ///
    /// Never a work session: one worked at the desk already counted at its credit point, and
    /// a minute of work before a closed lid is not a session.
    ///
    /// The break counts only after a break's worth of attended work, or the seconds between
    /// two stretches of sleep would bank a break a night. Postponed work is exempt: its break
    /// was earned before the postpone moved `startedAt`.
    static func settleByAbsence(
        _ plan: TimerPlan,
        at instant: TimerInstant,
        prefs: TimerPreferences,
        absence: TimeInterval
    ) -> (TimerPlan, [TimerEffect]) {
        let attended = instant.date.timeIntervalSince(plan.startedAt) - absence
        let earned = plan.phase == .postponedWork || attended >= prefs.restDuration
        let tally: [TimerEffect] = absence > 0 && earned ? [.record(.breakCompleted)] : []
        let (next, effects) = finishBreak(plan, at: instant, prefs: prefs, presenting: true)
        return (next, tally + effects)
    }
}
