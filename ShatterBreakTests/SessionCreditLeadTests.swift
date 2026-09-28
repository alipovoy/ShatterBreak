import Testing

@testable import ShatterBreak

/// Issue #71: a work session counts once its closing lead begins.
@Suite("Session credit lead", .tags(.timerState, .statistics))
struct SessionCreditLeadTests {
    @Test("the session counts at the credit point, and not again at the boundary")
    func countsOnceAtTheCreditPoint() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5, lead: 3))
        driver.act(.start)
        let interval = driver.plan.intervalID

        driver.run(6)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "The lead has not begun yet.")

        driver.run(1)
        #expect(driver.plan.sessionCredited, "Reaching the lead should spend the cycle's credit.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The session counts once its lead begins.")
        #expect(driver.remaining == 3, "The clock keeps counting the session down, not the lead up.")
        #expect(driver.plan.intervalID == interval, "Nothing restarted, so no view has an interval to re-key on.")

        driver.run(3)
        #expect(driver.phase == .rest, "The boundary should still hand over to the break.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The boundary must not count the session the credit point already did."
        )
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

    @Test("a credit the dark withheld is taken on return, not lost")
    func aWithheldCreditIsTakenOnReturn() {
        // Rest longer than work, so the away-reset threshold never intervenes and the
        // credit point is genuinely reached in the dark.
        var driver = ReducerDriver(prefs: .testing(work: 60, rest: 600, lead: 10))
        driver.act(.start)
        driver.act(.observedSleep)

        driver.drift(50)
        driver.reconcile()
        #expect(driver.phase == .work, "Nothing was credited, so nothing moved past the credit point.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "No one worked this session (issue #113).")

        // Back at the desk with ten seconds left, inside the lead.
        driver.act(.observedWake)
        #expect(driver.plan.sessionCredited, "Presence is what the credit point was waiting for.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "A withheld credit is not a lost one.")
    }

    @Test("leaving before the lead begins counts the break, not the session")
    func leavingBeforeTheLeadCountsNoSession() {
        // An away-reset counts the break alone, lead or not.
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
        // Gone before the lead began, by less than a break: the boundary still counts it.
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
        // In the same instant, as a replayed reconcile lands on a session the boundary just
        // auto-started: already inside its lead, and not yet worked for a second.
        driver.reconcile()
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "Starting a session is not working one.")

        driver.run(1)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The credit point is already behind it.")

        driver.run(1)
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "And it stays behind it.")
    }

    @Test("a postponed break resumed after a dark boundary counts no second session")
    func postponingAfterADarkBoundaryCountsOneSession() {
        // The boundary records the session here, so it must mark the credit taken too.
        var driver = ReducerDriver(prefs: .testing(work: 25, rest: 10, postpone: 3, lead: 3))
        driver.act(.start)
        driver.run(21)
        driver.act(.observedSleep)
        driver.run(4)
        #expect(driver.phase == .rest, "The setup needs a boundary crossed in the dark.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "Which counted the session the dark withheld.")

        driver.act(.observedWake)
        driver.act(.postpone)
        driver.run(3)
        #expect(driver.phase == .rest, "Postponed work hands back to the break it interrupted.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The postponed stint is the same session, however many times it hands back."
        )
    }
}
