import AppKit
import Testing

@testable import ShatterBreak

@Suite("Stalled transition detection and recovery", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct StalledTransitionTests {
    /// A timer whose work countdown ran out behind a sleep whose wake never arrived —
    /// the issue #87 shape.
    @MainActor
    private func makeStalledState(environment: TestEnvironment) async -> TimerState {
        let state = environment.makeTimerState()
        state.workDurationSecs = 2
        state.restDurationSecs = 5

        state.start()
        environment.workspaceNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await environment.advanceTime(by: 10)
        return state
    }

    @Test("an expiry blocked by a stuck asleep flag is reported as stalled")
    @MainActor
    func blockedExpiryIsDetected() async throws {
        let environment = TestEnvironment()
        let state = await makeStalledState(environment: environment)

        #expect(state.mode == .running, "The blocked transition should leave the mode untouched.")

        let report = try #require(state.stalledTransition)
        #expect(report.mode == .running, "The report should name the mode that owed a transition.")
        #expect(report.overdueSecs == 8, "The report should measure how far past the deadline it is.")
        #expect(report.wasAsleep, "A stuck flag is the diagnostic that classifies this as issue #87.")
    }

    @Test("an expiry lost without any sleep is still reported as stalled")
    @MainActor
    func lostExpiryWithoutSleepIsDetected() throws {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 2

        state.start()
        // Time passes with the expiry never delivered — a dropped callback rather than a
        // stuck flag. Detection is keyed to the overdue deadline, so the cause does not
        // matter; only this makes a future mechanism visible instead of silent.
        environment.elapseTimeWithoutTick(by: 10)

        let report = try #require(state.stalledTransition)
        #expect(report.overdueSecs == 8, "The stall should be measured from the deadline.")
        #expect(report.wasAsleep == false, "No sleep was involved, and the report must say so.")
    }

    @Test("an expiry still within the grace period is not yet a stall")
    @MainActor
    func expiryInFlightIsNotAStall() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 2

        state.start()
        // A callback is allowed to arrive late: the scheduler fires within a tolerance and
        // the hop back to the main actor costs more. Warning here would be a false positive.
        environment.elapseTimeWithoutTick(by: 2 + TimerState.stallGrace - 1)

        #expect(state.stalledTransition == nil, "An expiry in flight must not read as a stall.")
    }

    @Test("a sleep whose countdown has not run out is not a stall")
    @MainActor
    func sleepBeforeExpiryIsNotAStall() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 60

        state.start()
        environment.workspaceNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        environment.elapseTimeWithoutTick(by: 30)

        // Sleeping mid-countdown is routine: nothing is owed yet, so `handleWake()` still
        // owns the reconciliation.
        #expect(state.stalledTransition == nil, "A sleep before expiry must not read as a stall.")
    }

    @Test("idle owes no transition, so a stuck flag there is not a stall")
    @MainActor
    func idleNeverStalls() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 1

        state.start()
        state.stop()
        state.sleptAt = environment.now
        environment.elapseTimeWithoutTick(by: 60)

        #expect(state.mode == .idle)
        #expect(state.stalledTransition == nil, "Idle owes no transition, so it cannot stall.")
    }

    @Test("awaiting return owes no transition, so a stuck flag there is not a stall")
    @MainActor
    func awaitingReturnNeverStalls() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 4) { state.awaitingReturn }
        state.sleptAt = environment.now
        environment.elapseTimeWithoutTick(by: 60)

        #expect(state.awaitingReturn)
        #expect(state.stalledTransition == nil, "The break already finished; nothing is owed.")
    }

    @Test("a paused timer is not a stall, however long it sits")
    @MainActor
    func pausedNeverStalls() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5

        state.start()
        state.pause()
        environment.elapseTimeWithoutTick(by: 600)

        #expect(state.isPaused)
        #expect(state.stalledTransition == nil, "A pause has no deadline to be overdue against.")
    }

    @Test("a live deadline outside a counting mode is not a stall")
    @MainActor
    func liveDeadlineInANonCountingModeIsNotAStall() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 2

        state.start()
        // No current path leaves a deadline armed outside `isRunning` — every route out of a
        // counting mode freezes or clears first. Forcing the combination pins that as a local
        // rule rather than a property of the call graph.
        state.mode = .awaitingReturn
        environment.elapseTimeWithoutTick(by: 60)

        #expect(state.stalledTransition == nil, "A mode that owes no transition cannot stall.")
    }

    @Test("resuming a stall clears the flag and fires the overdue transition")
    @MainActor
    func resumingFiresTheOverdueTransition() async {
        let environment = TestEnvironment()
        let state = await makeStalledState(environment: environment)

        state.recoverFromStalledTransition()

        #expect(state.sleptAt == nil, "Resuming must clear the flag that blocked the transition.")
        #expect(state.stalledTransition == nil, "The stall must not survive its own recovery.")
        // The overdue transition fires as itself. Notably *not* what `handleWake()` would do:
        // it would read the stuck interval as an absence and reconcile against it, which for
        // a long stall discards the work session and raises a break instead (issue #89).
        #expect(state.isResting, "The work countdown that ran out should now enter its break.")
    }

    @Test("resuming a healthy timer does nothing")
    @MainActor
    func resumingWithoutAStallIsANoOp() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 60

        state.start()
        state.recoverFromStalledTransition()

        #expect(state.mode == .running, "A healthy timer must be left alone.")
        #expect(state.timeRemaining == 60, "Recovery must not disturb a running countdown.")
    }

    @Test("postponed work with no saved break falls back to a full one")
    @MainActor
    func postponedWorkWithoutSavedBreakStillRests() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: 2)
        state.workDurationSecs = 1
        state.restDurationSecs = 7

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()

        // The postponed expiry clears the countdown before restoring the break, so a missing
        // remainder used to park `.postponedWork` at 00:00 with nothing armed — a stall with
        // no sleep and no deadline to detect it by.
        state.savedRestRemaining = nil
        await environment.advanceTime(by: 2)

        #expect(state.isResting, "A missing remainder must still produce a break, not a dead timer.")
        #expect(state.timeRemaining == 7, "The fallback should be a full break.")
        #expect(state.canPostpone == false, "The postpone stays spent for this cycle.")
    }

    @Test("the report URL carries the diagnostics needed to act on it")
    func reportURLCarriesDiagnostics() throws {
        let report = StalledTransitionReport(
            mode: .resting,
            overdueSecs: 900,
            wasAsleep: false,
            appInfo: AppInfo(info: [
                "CFBundleShortVersionString": "1.4.2",
                "CFBundleVersion": "77",
                "AppBuildHash": "abc1234"
            ])
        )

        let url = try #require(report.reportURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        let body = try #require(items.first { $0.name == "body" }?.value)

        #expect(url.host() == "github.com", "The report should go to the tracker.")
        #expect(items.first { $0.name == "title" }?.value?.contains("resting") == true)
        #expect(body.contains("1.4.2"), "The build under test must be identifiable from the report.")
        #expect(body.contains("abc1234"), "The commit is what pins the report to a revision.")
        #expect(body.contains("15 minutes"), "The overdue duration should read as a duration.")
        #expect(body.contains("not the issue #87 family"), "A clear flag must rule out #87 in the body.")
    }

    @Test("a report from a stuck flag names the issue #87 family")
    func reportNamesTheSleepCauseWhenAsleep() throws {
        let report = StalledTransitionReport(mode: .running, overdueSecs: 60, wasAsleep: true)
        let url = try #require(report.reportURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)

        #expect(body.contains("issue #87 family"), "A stuck flag is the one cause we can name.")
        #expect(body.contains("stuck"), "The flag's state belongs in the diagnostics table.")
    }
}
