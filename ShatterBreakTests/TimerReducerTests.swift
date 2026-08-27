import Foundation
import Testing

@testable import ShatterBreak

/// The ordinary cycle through the pure reducer — the same behaviours the ``TimerState``
/// suites assert end to end. If a scenario holds here and fails there, the fault is in the
/// wiring, not the rules.
@Suite("Timer reducer cycle", .tags(.timerState))
struct TimerReducerTests {
    @Test("starting begins work with the configured duration and settles capture consent")
    func startBeginsWork() {
        var driver = ReducerDriver(prefs: .testing(work: 10))
        driver.act(.start)

        #expect(driver.phase == .work, "start should begin a work session.")
        #expect(driver.remaining == 10, "Work should begin with the configured duration.")
        #expect(
            driver.lastEffects.contains(.prepareCapturePermissions),
            "Capture consent is settled at the head of the work session, not mid-break (issue #90)."
        )
        #expect(
            driver.lastEffects.contains(.resetStatisticsForNewSession),
            "A start from idle is the stop→start boundary the opt-in tally reset applies to."
        )
    }

    @Test("work hands over to a full break and counts the session")
    func workHandsOverToRest() {
        var driver = ReducerDriver(prefs: .testing(work: 3, rest: 5))
        driver.act(.start)
        driver.run(3)

        #expect(driver.phase == .rest, "The work countdown reaching zero should enter the break.")
        #expect(driver.remaining == 5, "An uninterrupted handover gives the break its full duration.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The completed session should count once.")
        #expect(driver.lastEffects.contains(.showOverlay(.animated)), "A break beginning now plays its full intro.")
    }

    @Test("a break that runs out auto-starts the next session when auto-start is on")
    func breakAutoStartsNextSession() {
        var driver = ReducerDriver(prefs: .testing(work: 3, rest: 2, autoStartWork: true))
        driver.act(.start)
        driver.run(3)
        driver.run(2)

        #expect(driver.phase == .work, "Auto mode should begin the next work session when the break ends.")
        #expect(driver.remaining == 3, "The next session should start with the full work duration.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "A break that ran to completion should count.")
        #expect(driver.count(of: .dismissOverlay) == 1, "Starting work should take the break overlay down.")
    }

    @Test("a break that runs out parks in the break-end window when auto-start is off")
    func breakAwaitsUserWhenManual() {
        var driver = ReducerDriver(prefs: .testing(work: 3, rest: 2, autoStartWork: false))
        driver.act(.start)
        driver.run(3)
        driver.run(2)

        #expect(driver.phase == .awaitingReturn, "Manual mode should wait for the user after the break.")
        #expect(driver.remaining == 0, "An expired manual break has no time left to show.")
        #expect(
            driver.count(of: .showOverlay(.settled)) == 0,
            "The break overlay is already on screen; the rest-expiry path must not present a second one."
        )
    }

    @Test("the boundary is crossed once, however late the reconcile arrives")
    func lateReconcileCrossesOneBoundary() {
        var driver = ReducerDriver(prefs: .testing(work: 3, rest: 60))
        driver.act(.start)
        // A boundary timer that never fired. The machine was awake throughout, so this is a
        // lost callback, not an absence; it used to strand the timer at 00:00 (#106).
        driver.drift(45)
        driver.reconcile()

        #expect(driver.phase == .rest, "A late reconcile must still cross the boundary it missed.")
        #expect(driver.remaining == 60, "Time the user spent at the machine is not break taken.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The missed boundary counts exactly once.")
    }

    @Test("pausing freezes the remainder and resuming continues from it")
    func pauseAndResume() {
        var driver = ReducerDriver(prefs: .testing(work: 10))
        driver.act(.start)
        driver.run(4)
        driver.act(.pause)
        let frozen = driver.remaining

        driver.run(3)
        #expect(driver.remaining == frozen, "A paused countdown must not move.")
        #expect(driver.plan.phase == .work, "Pausing does not change the phase, only freezes it.")

        driver.act(.resume)
        driver.run(2)
        #expect(driver.remaining == frozen - 2, "Resuming should continue from the frozen remainder.")
    }

    @Test("pausing during a break skips it into work without counting a break")
    func pauseDuringRestSkipsIt() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 10))
        driver.act(.start)
        driver.run(2)
        #expect(driver.phase == .rest, "The setup should be resting before skipping.")

        driver.act(.pause)

        #expect(driver.phase == .work, "Skipping the break should start the next work session.")
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "A skipped break did not happen and must not count.")
        #expect(driver.lastEffects.contains(.dismissOverlay), "Skipping should take the break overlay down.")
    }

    @Test("stopping clears every cycle-scoped value")
    func stopClearsEverything() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 10, postpone: 3))
        driver.act(.start)
        driver.run(2)
        driver.act(.postpone)
        driver.act(.stop)

        #expect(driver.phase == .idle, "stop should return to idle.")
        #expect(driver.remaining == 0, "stop should leave nothing on the clock.")
        #expect(driver.plan.savedRestRemaining == nil, "stop must not leave a saved break behind.")
        #expect(driver.plan.postponeUsedThisCycle == false, "stop should free postpone for the next cycle.")
        #expect(driver.plan.unattendedSince == nil, "stop must not strand an absence timestamp (issue #87).")
    }

    @Test("returning early counts the break as taken and tallies the early return")
    func earlyReturnCountsBoth() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 10))
        driver.act(.start)
        driver.run(2)
        driver.act(.returnToWork)

        #expect(driver.phase == .work, "Returning early should begin the next work session.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "An early return still counts the break as taken.")
        #expect(driver.count(of: .record(.earlyReturn)) == 1, "The cut-short break should tally an early return.")
    }

    @Test("the routine return from the break-end window counts nothing")
    func routineReturnCountsNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 2, autoStartWork: false))
        driver.act(.start)
        driver.run(2)
        driver.run(2)
        #expect(driver.phase == .awaitingReturn, "The setup should park in the break-end window.")

        driver.act(.returnToWork)

        #expect(driver.phase == .work, "The return should begin work.")
        #expect(driver.count(of: .record(.earlyReturn)) == 0, "A return from awaiting-return is not an early return.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The break already counted when it expired.")
    }

    @Test("every phase entry is a distinct interval")
    func everyPhaseIsADistinctInterval() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 2))
        driver.act(.start)
        let work = driver.plan.intervalID
        driver.run(2)
        let rest = driver.plan.intervalID
        driver.run(2)
        let nextWork = driver.plan.intervalID

        // Views key their refresh loop on this; back-to-back sessions are identical in every
        // other field, which is how the menu bar came to render a finished one (#108).
        #expect(work != rest, "Work and its break must be distinguishable intervals.")
        #expect(rest != nextWork, "A break and the session after it must be distinguishable.")
        #expect(work != nextWork, "Consecutive work sessions must be distinguishable.")
    }
}

/// Postpone: one per cycle, giving the break time back rather than dropping it.
@Suite("Timer reducer postpone", .tags(.timerState))
struct TimerReducerPostponeTests {
    private func restingDriver(rest: TimeInterval = 10, postpone: TimeInterval = 3) -> ReducerDriver {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: rest, postpone: postpone))
        driver.act(.start)
        driver.run(2)
        return driver
    }

    @Test("postponing saves the break remainder and counts once")
    func postponeSavesRemainder() {
        var driver = restingDriver()
        driver.run(4)
        driver.act(.postpone)

        #expect(driver.phase == .postponedWork, "Postpone should switch into postponed work.")
        #expect(driver.remaining == 3, "Postponed work runs for the postpone duration.")
        #expect(driver.plan.savedRestRemaining == 6, "The break's remainder should be kept, not discarded.")
        #expect(driver.count(of: .record(.postponed)) == 1, "Using postpone should count once.")
        #expect(driver.lastEffects.contains(.dismissOverlay), "Postponing should take the break overlay down.")
    }

    @Test("a second postpone in the same cycle is ignored")
    func secondPostponeIgnored() {
        var driver = restingDriver()
        driver.act(.postpone)
        let afterFirst = driver.plan

        driver.act(.postpone)

        #expect(driver.plan == afterFirst, "A spent postpone must leave the plan untouched.")
        #expect(driver.count(of: .record(.postponed)) == 1, "The postpone should have counted exactly once.")
    }

    @Test("postponed work returns to the saved break, still spent for the cycle")
    func postponedWorkResumesSavedBreak() {
        var driver = restingDriver(rest: 10, postpone: 3)
        driver.run(4)
        driver.act(.postpone)
        driver.run(3)

        #expect(driver.phase == .rest, "Postponed work should hand back to the break it interrupted.")
        #expect(driver.remaining == 6, "The saved remainder should be restored.")
        #expect(driver.plan.postponeUsedThisCycle, "A resumed break keeps postpone spent for this cycle.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "A postponed cycle is still one work session; the resumed break must not count a second."
        )
    }

    @Test("postpone is restored for the next cycle's break")
    func postponeRestoredNextCycle() {
        var driver = restingDriver(rest: 4, postpone: 2)
        driver.act(.postpone)
        driver.run(2)
        #expect(driver.plan.postponeUsedThisCycle, "The resumed break should still have postpone spent.")

        driver.run(4)
        #expect(driver.phase == .work, "The resumed break should hand over to work.")
        driver.run(2)

        #expect(driver.phase == .rest, "The next cycle should reach its own break.")
        #expect(driver.plan.postponeUsedThisCycle == false, "A brand-new cycle's break restores postpone.")
    }

    @Test("pausing postponed work freezes it and resumes into postponed work")
    func pauseDuringPostponedWork() {
        var driver = restingDriver(rest: 10, postpone: 4)
        driver.act(.postpone)
        driver.run(1)
        driver.act(.pause)
        let frozen = driver.remaining

        driver.run(5)
        #expect(driver.remaining == frozen, "Postponed work must stay frozen while paused.")

        driver.act(.resume)
        #expect(driver.phase == .postponedWork, "Resuming should restore postponed work, not plain work.")
        driver.run(3)
        #expect(driver.phase == .rest, "The postponed work should still hand back to the break.")
    }
}
