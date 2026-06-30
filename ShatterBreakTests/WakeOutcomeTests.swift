import Testing

@testable import ShatterBreak

/// Exercises the pure wake-reconciliation rule across the grid worked out for a 25-minute
/// work / 5-minute break cycle (issues #69, #72). `W` is the work time remaining when
/// sleep began; durations are in minutes for readability.
@Suite("WakeOutcome resolution", .tags(.timerState, .sleepWake))
struct WakeOutcomeTests {
    private func resolve(
        away: Double,
        workRemaining: Double,
        restDuration: Double = 5,
        isPostponedWork: Bool = false,
        savedRestRemaining: Double? = nil
    ) -> WakeOutcome {
        WakeOutcome.resolve(
            isPostponedWork: isPostponedWork,
            away: away,
            workRemaining: workRemaining,
            restDuration: restDuration,
            savedRestRemaining: savedRestRemaining
        )
    }

    @Test("a short absence inside the work period resumes work")
    func shortAbsenceResumesWork() {
        // Early/mid session: plenty of work left, the absence is absorbed.
        #expect(resolve(away: 2, workRemaining: 20) == .resumeWork)
        #expect(resolve(away: 4, workRemaining: 5) == .resumeWork)
        #expect(resolve(away: 2, workRemaining: 3) == .resumeWork)
    }

    @Test("a full break's absence starts a fresh session regardless of work left")
    func longAbsenceStartsFreshSession() {
        #expect(resolve(away: 6, workRemaining: 20) == .startFreshSession)
        #expect(resolve(away: 6, workRemaining: 5) == .startFreshSession)
        #expect(resolve(away: 6, workRemaining: 1) == .startFreshSession)
    }

    @Test("an absence crossing into the break resumes the prorated remainder")
    func crossingAbsenceResumesProratedBreak() {
        // Whole time away is credited as rest: break - away.
        #expect(resolve(away: 2, workRemaining: 1) == .resumeBreak(remaining: 3, refreshingPostpone: true))
        #expect(resolve(away: 4, workRemaining: 1) == .resumeBreak(remaining: 1, refreshingPostpone: true))
        #expect(resolve(away: 4, workRemaining: 3) == .resumeBreak(remaining: 1, refreshingPostpone: true))
    }

    @Test("the reset and work boundaries are inclusive on the expected side")
    func boundariesResolveConsistently() {
        // away == rest duration is a full break → fresh session.
        #expect(resolve(away: 5, workRemaining: 1) == .startFreshSession)
        // away == work remaining stays in work (resumes with zero left, expiring normally).
        #expect(resolve(away: 3, workRemaining: 3) == .resumeWork)
    }

    @Test("a postponed break resumes its saved remainder, not a full rest")
    func postponedBreakResumesSavedRemainder() {
        // Saved remainder 8, away 6 spilled past 5 of postpone work → 8 - 6 = 2 left.
        #expect(
            resolve(away: 6, workRemaining: 5, restDuration: 10, isPostponedWork: true, savedRestRemaining: 8)
                == .resumeBreak(remaining: 2, refreshingPostpone: false)
        )
    }

    @Test("an absence covering the whole saved remainder starts a fresh session")
    func postponedBreakFullyCoveredStartsFresh() {
        // Saved remainder 2, away 3 spilled past 1 of postpone work → remainder exhausted.
        #expect(
            resolve(away: 3, workRemaining: 1, restDuration: 10, isPostponedWork: true, savedRestRemaining: 2)
                == .startFreshSession
        )
    }
}
