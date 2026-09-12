import Testing

@testable import ShatterBreak

/// Issue #71: a work session is counted once its closing lead begins, so the minutes
/// between "I'm done" and the boundary stop deciding whether the session happened.
@Suite("Session credit lead", .tags(.timerState, .statistics))
struct SessionCreditLeadTests {
    @Test("the session counts at the credit point, and not again at the boundary")
    func countsOnceAtTheCreditPoint() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)

        driver.run(6)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "The lead has not begun yet.")

        driver.run(1)
        #expect(driver.plan.sessionCredited, "Reaching the lead should spend the cycle's credit.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The session counts once its lead begins.")

        driver.run(3)
        #expect(driver.phase == .rest, "The boundary should still hand over to the break.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The boundary must not count the session the credit point already did."
        )
    }

    @Test("counting the session leaves the countdown alone")
    func theCountdownRunsThrough() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)
        let interval = driver.plan.intervalID

        driver.run(8)

        #expect(driver.remaining == 2, "The clock keeps counting the session down, not the lead up.")
        #expect(driver.plan.intervalID == interval, "Nothing restarted, so no view has an interval to re-key on.")
    }

    @Test("leaving after the credit point counts the session as well as the break")
    func leavingAfterTheCreditPointCountsBoth() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)
        // Done with the piece of work, two seconds still on the clock, lid closed.
        driver.run(8)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The work was done before the lid closed.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "And the absence served as the break.")
        #expect(driver.phase == .work, "A fresh session waits on return.")
    }

    @Test("without a lead the same absence still counts only the break")
    func theBugThisFixesNeedsTheLead() {
        // The behaviour issue #71 reports, and the default this ships with: identical
        // timeline, no lead, and the session the user worked goes uncounted.
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.run(8)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "Nothing crossed the boundary.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "Only the break is credited.")
    }

    @Test("an unattended machine does not take the credit point")
    func anUnattendedMachineDoesNotTakeTheCredit() {
        // Rest longer than work, so the away-reset threshold never intervenes and the
        // credit point is genuinely reached in the dark.
        var driver = ReducerDriver(prefs: .testing(work: 60, rest: 600, lead: 10))
        driver.act(.start)
        driver.act(.observedSleep)

        driver.drift(50)
        driver.reconcile()

        #expect(driver.phase == .work, "Nothing was credited, so nothing moved past the credit point.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "No one worked this session (issue #113).")
    }

    @Test("returning before the boundary takes the credit the dark withheld")
    func returningTakesAWithheldCredit() {
        var driver = ReducerDriver(prefs: .testing(work: 60, rest: 600, lead: 10))
        driver.act(.start)
        driver.act(.observedSleep)
        driver.drift(50)
        driver.reconcile()

        // Back at the desk with ten seconds left, inside the lead.
        driver.act(.observedWake)

        #expect(driver.plan.sessionCredited, "Presence is what the credit point was waiting for.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "A withheld credit is not a lost one.")
    }

    @Test("leaving before the lead begins counts the break, not the session")
    func leavingBeforeTheLeadCountsNoSession() {
        // The bound the lead must not widen: without it, this is an away-reset that counts
        // the break alone, and turning the lead on must not turn it into a worked session.
        var driver = ReducerDriver(prefs: .testing(work: 25, rest: 5, lead: 3))
        driver.act(.start)
        driver.run(20)
        driver.act(.observedSleep)

        // The credit point at 22 passes in the dark; by the boundary the absence is a
        // whole break long.
        driver.run(2)
        driver.run(3)

        #expect(driver.phase == .work, "A break-length absence settles the cycle and starts a fresh session.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Five of twenty-five minutes were missed; a three-minute lead does not cover that."
        )
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The absence served as the break.")
    }

    @Test("the boundary still counts a session the dark withheld at its credit point")
    func theBoundaryCountsAWithheldSession() {
        // The second chance the strict guard leaves open: gone before the lead began, but by
        // less than a break, so the boundary arrives with the absence short of the away-reset
        // — where the session counted before the lead existed.
        var driver = ReducerDriver(prefs: .testing(work: 25, rest: 5, lead: 3))
        driver.act(.start)
        driver.run(21)
        driver.act(.observedSleep)

        // The credit point at 22 passes in the dark.
        driver.run(1)
        #expect(driver.plan.sessionCredited == false, "Nobody was there to take the credit.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "So it is withheld, not lost.")

        driver.run(3)
        #expect(driver.phase == .rest, "Four seconds away is short of a break, so the boundary begins one.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The boundary judges an uncredited session exactly as it did before the lead."
        )
    }

    @Test("leaving inside the lead counts the session as well as the break")
    func leavingInsideTheLeadCountsBoth() {
        var driver = ReducerDriver(prefs: .testing(work: 25, rest: 5, lead: 3))
        driver.act(.start)
        // Past the credit point at the desk, so the session is already banked.
        driver.run(23)
        driver.act(.observedSleep)

        driver.drift(7)
        driver.reconcile()

        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "Twenty-three of twenty-five were worked.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "And the absence served as the break.")
    }

    @Test("a pause past the credit point freezes and resumes into the break")
    func pausingPastTheCreditPointBehavesLikeWork() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)
        driver.run(8)
        driver.act(.pause)

        driver.drift(30)
        driver.reconcile()
        #expect(driver.phase == .work, "A counted session is still a work session.")
        #expect(driver.remaining == 2, "A paused countdown must not move.")

        driver.act(.resume)
        driver.run(2)
        #expect(driver.phase == .rest, "The resumed remainder should still reach the break.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "And still count exactly one session.")
    }

    @Test("a reconcile later than the lead crosses both points at once")
    func aLateReconcileCrossesBothPoints() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)

        // Awake the whole time, nothing reconciled: a lost boundary timer, not an absence.
        driver.drift(10)
        driver.reconcile()

        #expect(driver.phase == .rest, "A late reconcile must still reach the break.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "One session, not one per point crossed.")
        #expect(driver.count(of: .showOverlay(.animated)) == 1, "And one break on screen.")
    }

    @Test("a lead as long as the session counts it at the first tick, once")
    func anOversizedLeadCountsAtTheStart() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 30))
        driver.act(.start)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "Starting a session is not working one.")

        driver.run(1)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The credit point is already behind it.")

        driver.run(1)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "And it stays behind it.")
    }

    @Test("a postponed break resumed after the credit point counts no second session")
    func postponingCountsOneSession() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, postpone: 3, lead: 3))
        driver.act(.start)
        driver.run(7)
        driver.run(3)
        #expect(driver.phase == .rest, "The setup needs a break to postpone.")

        driver.act(.postpone)
        driver.run(3)
        #expect(driver.phase == .rest, "Postponed work hands back to the break it interrupted.")

        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The postponed stint is the same session, however many times it hands back."
        )
    }
}

/// The half a reducer test cannot reach: the lead is a preference, and the clock has to be
/// armed for it.
@Suite("Session credit lead through TimerState", .tags(.timerState, .statistics), .timeLimit(.minutes(1)))
struct TimerStateSessionLeadTests {
    @MainActor
    private func makeState(_ environment: TestEnvironment, lead: Double) -> TimerState {
        environment.defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        environment.defaults.set(true, forKey: PreferenceKeys.countSessionEarly)
        environment.defaults.set(lead, forKey: PreferenceKeys.sessionLeadSecs)
        return environment.makeTimerState()
    }

    @Test("the clock is armed for the credit point, not the end of the session")
    @MainActor
    func theClockIsArmedForTheCreditPoint() async {
        let environment = TestEnvironment()
        let state = makeState(environment, lead: 3)
        state.workDurationSecs = 10
        state.restDurationSecs = 5

        state.start()
        #expect(environment.clock.scheduledBoundary == 7, "The next thing due is the credit point.")
        let interval = state.countdownIntervalID

        await environment.advanceTime(by: 7)
        #expect(state.statistics.current.workSessionsCompleted == 1, "The session counts as its lead begins.")
        #expect(state.mode == .running, "Nothing the user can see has changed: this is still work.")
        #expect(state.countdownIntervalID == interval, "And still the same countdown.")
        #expect(environment.clock.scheduledBoundary == 3, "What is due now is the break.")

        await environment.advanceTime(by: 3)
        #expect(state.isResting, "The boundary should still begin the break.")
        #expect(state.statistics.current.workSessionsCompleted == 1, "Which counts no second session.")
    }

    @Test("the lead does nothing while statistics are not being tracked")
    @MainActor
    func theLeadNeedsSomethingToCount() async {
        let environment = TestEnvironment()
        // Switched on, but with the tally that owns it turned off — the state left behind by
        // turning Track Statistics off, which also takes this switch off screen.
        environment.defaults.set(true, forKey: PreferenceKeys.countSessionEarly)
        environment.defaults.set(3, forKey: PreferenceKeys.sessionLeadSecs)
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 5

        state.start()
        #expect(
            environment.clock.scheduledBoundary == 10,
            "Nothing is counted, so there is no credit point to arm for."
        )
    }

    @Test("the stored lead does nothing until it is switched on")
    @MainActor
    func theLeadIsOffUntilSwitchedOn() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        // The field keeps a value of its own; the toggle is what makes it apply.
        environment.defaults.set(3, forKey: PreferenceKeys.sessionLeadSecs)
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 5

        state.start()
        #expect(environment.clock.scheduledBoundary == 10, "With no lead, the boundary is the only thing due.")

        await environment.advanceTime(by: 7)
        #expect(state.statistics.current.workSessionsCompleted == 0, "A session still counts where it always did.")
    }
}
