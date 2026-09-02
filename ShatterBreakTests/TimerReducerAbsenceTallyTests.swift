import Testing

@testable import ShatterBreak

/// What a cycle settled by an absence writes to the tally (issue #111).
///
/// One rule, two halves. The break the absence stood in for counts, because a break taken by
/// walking away is still a break taken. The work session never does: one finished at the desk
/// was counted by the boundary it crossed, so anything counted here would be a countdown the
/// wall clock ran out on with nobody in the room.
///
/// The break is credited only to a session someone sat through for a break's worth first —
/// unless a postpone already earned it. Everything in "Absences that earn nothing" is a way
/// the machine can look busy while the room is empty, and the floor is what tells them apart.
@Suite("Timer reducer absence tallies", .tags(.timerState, .sleepWake))
struct TimerReducerAbsenceTallyTests {
    // MARK: - Breaks an absence earns

    @Test("walking away after real work counts the break it served, but never the session")
    func absenceAfterRealWorkCountsTheBreakOnly() {
        var driver = ReducerDriver(prefs: .testing(work: 100, rest: 5))
        driver.act(.start)
        driver.run(10)
        driver.sleepMachine(20)
        driver.reconcile()

        #expect(driver.phase == .work, "The absence served as the break, so a fresh session starts.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The twenty seconds away were a break taken.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Ten seconds of a hundred is not a session completed, whatever the clock did afterwards."
        )
    }

    @Test("a lunch longer than the whole work period is still one break")
    func lunchOutlastingTheWorkPeriodCountsOneBreak() {
        var driver = ReducerDriver(prefs: .testing(work: 1_800, rest: 300))
        driver.act(.start)
        driver.run(1_500)
        driver.sleepMachine(3_600)
        driver.reconcile()

        #expect(
            driver.count(of: .record(.breakCompleted)) == 1,
            "A morning at the desk earns the break the lunch then served."
        )
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "The countdown ran out over lunch, not at the desk, so no session completed."
        )
    }

    @Test("a break served by an absence during postponed work counts once")
    func absenceDuringPostponedWorkCountsTheBreak() {
        var driver = ReducerDriver(prefs: .testing(work: 8, rest: 5, postpone: 8))
        driver.act(.start)
        driver.run(8)
        driver.act(.postpone)
        driver.run(6)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .work, "The absence covered the postponed break, so a fresh session starts.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The break the user put off was finally taken.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The session counted when it first entered rest; the postponed remainder must not count another."
        )
    }

    @Test("leaving the moment a break is postponed still counts it")
    func absenceRightAfterAPostponeCountsTheBreak() {
        var driver = ReducerDriver(prefs: .testing(work: 100, rest: 10, postpone: 20))
        driver.act(.start)
        driver.run(100)
        driver.act(.postpone)
        // A second at the desk: under the floor this absence would face in `.work`.
        driver.run(1)
        driver.sleepMachine(15)
        driver.reconcile()

        #expect(
            driver.count(of: .record(.breakCompleted)) == 1,
            "The postponed break was earned by the session that reached it, not by the reprieve."
        )
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "Only the session that entered rest; the reprieve must not count a second."
        )
    }

    @Test("an absence too short to reset still counts the postponed break it covered")
    func shortAbsenceCoveringSavedBreakCountsIt() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 3, postpone: 5))
        driver.act(.start)
        driver.run(2)
        // 1s of break left when the postpone starts.
        driver.run(2)
        driver.act(.postpone)
        driver.run(4)
        // 2s away: under the 3s away-reset threshold, so this crosses the postponed-work
        // boundary rather than resetting — and covers the whole 1s remainder on the way.
        driver.sleepMachine(2)
        driver.reconcile()

        #expect(driver.phase == .work, "The saved break the absence covered leaves nothing to resume.")
        #expect(
            driver.count(of: .record(.breakCompleted)) == 1,
            "A break served by an absence counts on this route too, not only past the threshold (issue #111)."
        )
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The session counted when it first entered rest; the covered remainder must not count another."
        )
    }

    @Test("the wake that ends a credited absence adds nothing to it")
    func theWakeAfterACreditedAbsenceAddsNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.run(600)
        driver.act(.observedSleep)

        // The display goes dark and a heartbeat resolves the absence into a break.
        driver.drift(400)
        driver.reconcile()
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The setup should have credited one break.")

        // The user comes back. `returned` clears `unattendedSince` before reconciling, so the
        // empty-room guard cannot be what stops this crossing counting a second break.
        driver.drift(600)
        driver.act(.observedWake)

        #expect(
            driver.count(of: .record(.breakCompleted)) == 1,
            "One absence, one break: the wake must not re-tally what the heartbeat already resolved."
        )
    }

    // MARK: - Absences that earn nothing

    @Test("a minute of work before a closed lid banks nothing overnight")
    func aMinuteOfWorkBeforeAClosedLidCountsNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.run(60)
        driver.sleepMachine(15 * 3_600)
        driver.reconcile()

        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Fifteen hours of closed lid is not a session worked, however far past the deadline it lands."
        )
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "A minute at the desk has not earned a break.")
    }

    @Test("maintenance wakes between stretches of sleep bank nothing")
    func maintenanceWakesInAnEmptyRoomCountNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.act(.observedSleep)

        // A laptop waking for a second every hour to check mail, all night. Each wake retires
        // the absence, so the empty-room guard is not what has to catch these.
        for _ in 0..<8 {
            driver.sleepMachine(3_600)
            driver.act(.observedWake)
            driver.run(1)
            driver.act(.observedSleep)
        }

        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "Nobody worked through the night.")
        #expect(
            driver.count(of: .record(.breakCompleted)) == 0,
            "A second of running time between two hours of sleep is not someone taking a break."
        )
    }

    @Test("a clock jump at the desk is not a break")
    func aClockJumpAtTheDeskCountsNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.run(30)
        // Indistinguishable from sleep by measurement: the wall clock leaps an hour while the
        // awake clock does not. The timer restarting is old behaviour; the tally must not
        // follow it.
        driver.sleepMachine(3_600)
        driver.reconcile()

        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "The user never left their desk.")
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "Nor did they take a break.")
    }
}
