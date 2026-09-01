import Testing

@testable import ShatterBreak

/// What happens when the user goes away.
///
/// The policy is unchanged; the input is not. An absence is *measured* from the two clocks
/// rather than inferred from a sleep notification that has to arrive, and be matched by a
/// wake, for anything to happen.
@Suite("Timer reducer absences", .tags(.timerState, .sleepWake))
struct TimerReducerAbsenceTests {
    // MARK: - Absences measured with no notification at all

    @Test("a short absence inside the work period just keeps counting")
    func shortAbsenceKeepsCountingWork() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.sleepMachine(2)
        driver.reconcile()

        #expect(driver.phase == .work, "An absence shorter than the break leaves work running.")
        #expect(driver.remaining == 8, "The countdown never pauses on sleep, so the time away is spent (issue #4).")
    }

    @Test("an absence as long as a break starts a fresh session, with no notification involved")
    func longAbsenceStartsFreshSession() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.run(5)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .work, "An absence that served as the break resumes work (issue #69).")
        #expect(driver.remaining == 10, "The session is fresh, not the stale one the user walked away from.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The countdown ran out during the absence, so the session completed (issue #111)."
        )
        #expect(
            driver.count(of: .record(.breakCompleted)) == 1,
            "The absence is the break: the route that serves one must tally one (issue #111)."
        )
    }

    @Test("an absence spilling from work into the break resumes it prorated, crediting the whole absence")
    func absenceSpillingIntoBreakResumesProrated() {
        var driver = ReducerDriver(prefs: .testing(work: 5, rest: 10))
        driver.act(.start)
        driver.sleepMachine(7)
        driver.reconcile()

        // The whole 7s away is credited, not just the 2s past the boundary.
        #expect(driver.phase == .rest, "The absence crossed the work boundary into the break.")
        #expect(driver.remaining == 3, "The break resumes with the whole absence credited as rest.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The work session completed off-screen.")
        #expect(driver.lastEffects.contains(.showOverlay(.animated)), "A break with time left plays its full intro.")
    }

    @Test("an absence exactly as long as the break threshold starts fresh")
    func absenceAtThresholdStartsFresh() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.run(9)
        driver.sleepMachine(5)
        driver.reconcile()

        #expect(driver.phase == .work, "An absence of exactly one break length is a break.")
        #expect(driver.remaining == 10, "The reset boundary is inclusive, so the session restarts.")
    }

    @Test("an absence ending exactly at the work boundary is credited like any crossing")
    func absenceEndingAtWorkBoundaryIsCredited() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.run(7)
        driver.sleepMachine(3)
        driver.reconcile()

        // One rule for every crossing. The old design branched on `away <=
        // workRemaining`, giving a full break at this exact instant and docking one a
        // millisecond either side.
        #expect(driver.phase == .rest, "Work ran out exactly as the absence ended.")
        #expect(driver.remaining == 2, "The absence is credited as rest, as it is for any crossing.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 1, "The session completed and should count.")
    }

    @Test("a break that elapses during an absence completes once and hands over")
    func breakElapsedDuringAbsenceCompletesOnce() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 5))
        driver.act(.start)
        driver.run(2)
        #expect(driver.phase == .rest, "The setup should be resting before the absence.")

        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .work, "A break that ran out while away should hand over to work.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The break ran to completion on the wall clock.")
    }

    @Test("an absence during a break shorter than its remainder just spends the break")
    func shortAbsenceDuringBreakSpendsIt() {
        var driver = ReducerDriver(prefs: .testing(work: 2, rest: 10))
        driver.act(.start)
        driver.run(2)
        driver.sleepMachine(4)
        driver.reconcile()

        #expect(driver.phase == .rest, "A break with time left keeps resting.")
        #expect(driver.remaining == 6, "Time away during a break is break taken (issue #4).")
        #expect(driver.count(of: .dismissOverlay) == 0, "The break overlay should stay up until the break ends.")
    }

    @Test("a long absence during postponed work discards the saved break and starts fresh")
    func longAbsenceDuringPostponedWorkStartsFresh() {
        var driver = ReducerDriver(prefs: .testing(work: 8, rest: 5, postpone: 4))
        driver.act(.start)
        driver.run(8)
        driver.act(.postpone)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .work, "A long absence during postponed work starts a fresh session (issue #69).")
        #expect(driver.remaining == 8, "The fresh session should restore the full work duration.")
        #expect(driver.plan.savedRestRemaining == nil, "The in-flight saved break must be discarded, not leaked.")
    }

    @Test("an absence crossing into a postponed break resumes the saved remainder, prorated")
    func absenceCrossingIntoPostponedBreak() {
        var driver = ReducerDriver(prefs: .testing(work: 1, rest: 10, postpone: 5))
        driver.act(.start)
        driver.run(1)
        driver.act(.postpone)
        // 6s away: past the 5s of postponed work, inside the 10s saved break.
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .rest, "Crossing into the saved break should re-enter rest.")
        #expect(driver.remaining == 4, "The saved break resumes with the whole absence credited (10 - 6).")
        #expect(driver.plan.postponeUsedThisCycle, "A resumed postponed break keeps postpone spent for the cycle.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The session counted when it first entered rest; the resumed break must not count another."
        )
        #expect(driver.lastEffects.contains(.showOverlay(.animated)), "The overlay dismissed at postpone comes back.")
    }

    @Test("an absence covering the whole saved break starts a fresh session")
    func absenceCoveringSavedBreakStartsFresh() {
        var driver = ReducerDriver(prefs: .testing(work: 1, rest: 10, postpone: 5))
        driver.act(.start)
        driver.run(1)
        driver.run(8)
        // 2s of break left when the postpone starts.
        driver.act(.postpone)
        #expect(driver.plan.savedRestRemaining == 2, "The setup should leave a short saved break.")

        // 8s away: past the 5s of postponed work and past the whole 2s remainder, but still
        // under the full-break reset threshold of 10s.
        driver.sleepMachine(8)
        driver.reconcile()

        #expect(driver.phase == .work, "A saved break the absence fully covered leaves nothing to resume.")
        #expect(driver.remaining == 1, "The fresh session should restore the full work duration.")
    }

    @Test("a manual-mode absence that served as the break presents the window already settled")
    func manualModeLongAbsencePresentsSettledWindow() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 3, autoStartWork: false))
        driver.act(.start)
        driver.sleepMachine(4)
        driver.reconcile()

        #expect(driver.phase == .awaitingReturn, "Manual mode must not silently restart work (issue #69).")
        #expect(
            driver.lastEffects == [.showOverlay(.settled)],
            "A break that already elapsed is announced settled: no shake, no entrance sound (issues #76, #94)."
        )
    }

    @Test("a user pause is not disturbed by an absence of any length")
    func pauseSurvivesAbsence() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.run(3)
        driver.act(.pause)
        let frozen = driver.remaining

        driver.sleepMachine(3_600)
        driver.reconcile()

        #expect(driver.plan.pausedAt != nil, "A manual pause must not auto-resume; only the user resumes it.")
        #expect(driver.remaining == frozen, "A paused countdown keeps its frozen time across an absence.")
        #expect(driver.lastEffects.isEmpty, "A paused timer owes the world nothing.")
    }

    // MARK: - The tally an absence earns (issue #111)

    @Test("walking away mid-session counts the break it served, but not the session")
    func absenceMidSessionCountsTheBreakOnly() {
        var driver = ReducerDriver(prefs: .testing(work: 100, rest: 5))
        driver.act(.start)
        driver.run(10)
        driver.sleepMachine(20)
        driver.reconcile()

        #expect(driver.phase == .work, "The absence served as the break, so a fresh session starts.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The twenty seconds away were a break taken.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Ten seconds of a hundred is not a session completed; only the countdown running out is."
        )
    }

    @Test("a lunch longer than the work period still counts the morning that earned it")
    func absenceOutlastingTheWorkPeriodCountsTheSession() {
        var driver = ReducerDriver(prefs: .testing(work: 1_800, rest: 300))
        driver.act(.start)
        driver.run(1_500)
        // An hour away: longer than the whole work period, but not longer than the session
        // that has been running since the user sat down.
        driver.sleepMachine(3_600)
        driver.reconcile()

        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "Judging presence by the absence against the phase's *duration* would drop this session."
        )
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The lunch was the break.")
    }

    @Test("a break served by an absence during postponed work counts the break alone")
    func absenceDuringPostponedWorkCountsTheBreakOnly() {
        var driver = ReducerDriver(prefs: .testing(work: 8, rest: 5, postpone: 4))
        driver.act(.start)
        driver.run(8)
        driver.act(.postpone)
        driver.run(2)
        driver.sleepMachine(6)
        driver.reconcile()

        #expect(driver.phase == .work, "The absence covered the postponed break, so a fresh session starts.")
        #expect(driver.count(of: .record(.breakCompleted)) == 1, "The break the user put off was finally taken.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "The session counted when it first entered rest; the postponed remainder must not count another."
        )
    }

    @Test("an absence covering a whole session counts nothing, however it was measured")
    func absenceCoveringTheWholePhaseCountsNothing() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        // Away from the moment the session began, with no sleep notification to mark it: the
        // empty room restarting itself, which `ranUnattended` alone would not catch.
        driver.sleepMachine(3_600)
        driver.reconcile()

        #expect(driver.phase == .work, "The session still restarts; only the tally is withheld.")
        #expect(driver.count(of: .record(.workSessionCompleted)) == 0, "Nobody worked a second of it.")
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "Nor was there anyone to take the break.")
    }

    // MARK: - The catch-up trap

    @Test("a three-hour absence resolves once, not once per cycle it spans")
    func threeHourAbsenceResolvesOnce() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.sleepMachine(3 * 3_600)
        driver.reconcile()
        // Reconciling again is what the heartbeat, the boundary timer and a wake
        // notification all do within milliseconds of each other.
        driver.reconcile()
        driver.reconcile()

        #expect(driver.phase == .work, "Three hours away served as the break.")
        #expect(driver.remaining == 1_500, "The fresh session should restore the full work duration.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Replaying the boundaries a long absence spans would inflate the tally with sessions nobody worked."
        )
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "No break was ever presented, so none completed.")
        #expect(driver.count(of: .showOverlay(.animated)) == 0, "Nothing should queue a stack of break overlays.")
    }

    @Test("a machine still unattended does not reset the session on every reconcile")
    func ongoingAbsenceResolvesOncePerThreshold() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        // The display slept and never woke: the notification arrives, the matching wake
        // never does. Under the old design this stranded the timer permanently.
        driver.act(.observedSleep)
        driver.drift(600)
        driver.reconcile()
        #expect(driver.remaining == 1_500, "Ten minutes unattended served as the break, so the session restarts.")

        // Heartbeats keep arriving while the display stays dark. The absence already
        // credited must not be spent a second time.
        driver.drift(30)
        driver.reconcile()
        driver.drift(30)
        driver.reconcile()

        #expect(driver.remaining == 1_500 - 60, "A credited absence must not restart the session again.")
    }

    @Test("resetting a session in an empty room does not settle capture consent")
    func absenceResetsDoNotProbeForCaptureConsent() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        #expect(
            driver.count(of: .prepareCapturePermissions) == 1,
            "Starting a session the user is present for settles the consent its break needs (issue #90)."
        )

        driver.act(.observedSleep)
        // Hours with the display dark and the machine awake. Restarting the session each
        // threshold keeps an empty room from inflating the tally, but settling consent can
        // raise a dialog nobody is there to answer.
        for _ in 0..<12 {
            driver.drift(300)
            driver.reconcile()
        }

        #expect(
            driver.count(of: .prepareCapturePermissions) == 1,
            "An unattended machine must not be asked for capture consent, over and over, with nobody there."
        )
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "Nor should an hour in an empty room bank sessions nobody worked."
        )
    }

    @Test("returning credits the whole absence, not the sliver since it was last resolved")
    func returningCreditsTheWholeAbsence() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.act(.observedSleep)

        // An hour away with the display dark. The session quietly restarted several times
        // over; the last of those was only moments ago.
        for _ in 0..<12 {
            driver.drift(300)
            driver.reconcile()
        }
        driver.drift(30)

        driver.act(.observedWake)

        // Measuring only the seconds since the last restart would hand back a session
        // already minutes old; an hour away is owed a whole one.
        #expect(driver.phase == .work, "An hour away served as the break.")
        #expect(driver.remaining == 1_500, "The session the user comes back to must be whole.")
        #expect(driver.plan.unattendedSince == nil, "The absence is over.")
        #expect(
            driver.lastEffects.contains(.prepareCapturePermissions),
            "The session they actually return to settles the consent its break will need (issue #90)."
        )
        #expect(
            driver.count(of: .record(.breakCompleted)) == 0,
            "One absence, one decision: the wake must not re-tally a break the crossings already resolved."
        )
    }

    @Test("anything the user does is proof they are at the machine")
    func userActionRetiresAnAbsence() {
        var driver = ReducerDriver(prefs: .testing(work: 1_500, rest: 300))
        driver.act(.start)
        driver.act(.observedSleep)
        driver.drift(600)

        // No wake notification: the user moved the mouse and pressed Pause, which is better
        // evidence than one.
        driver.act(.pause)

        #expect(driver.plan.unattendedSince == nil, "A user action must retire the absence a notification claimed.")
    }
}

/// Notifications improve an absence measurement; they never authorise one.
@Suite("Timer reducer absence notifications", .tags(.timerState, .sleepWake))
struct TimerReducerAbsenceNotificationTests {

    @Test("a display sleep with no matching wake still resolves on the next reconcile")
    func displaySleepWithoutWakeStillResolves() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.act(.observedSleep)
        // The machine stayed awake, so only the notification says the user is gone — and no
        // wake ever comes.
        driver.drift(6)
        driver.reconcile()

        #expect(driver.phase == .work, "The absence should resolve without the wake notification.")
        #expect(driver.remaining == 10, "A display asleep for a full break is still a break (issue #69).")
    }

    @Test("a wake notification retires the absence it was measured from")
    func wakeRetiresTheAbsence() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.act(.observedSleep)
        driver.drift(2)
        driver.act(.observedWake)

        #expect(driver.plan.unattendedSince == nil, "A wake means the user is back; the absence is over.")
        #expect(driver.remaining == 8, "A short absence leaves the session running.")

        // Without retiring it, this boundary would read the old timestamp as an
        // eight-second absence and wrongly prorate the break.
        driver.run(8)
        #expect(driver.remaining == 5, "The break should get its full duration, not one docked by a stale absence.")
    }

    @Test("a duplicate sleep notification keeps the original timestamp")
    func duplicateSleepKeepsOriginalTimestamp() {
        var driver = ReducerDriver(prefs: .testing(work: 10, rest: 5))
        driver.act(.start)
        driver.act(.observedSleep)
        let first = driver.plan.unattendedSince

        // System sleep and display sleep both fire; the second must not shorten the absence.
        driver.drift(3)
        driver.act(.observedSleep)

        #expect(driver.plan.unattendedSince == first, "The later notification must not restart the measurement.")
    }
}
