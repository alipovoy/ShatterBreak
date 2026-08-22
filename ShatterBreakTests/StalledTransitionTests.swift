import AppKit
import Testing

@testable import ShatterBreak

@Suite("Stalled transition detection and recovery", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct StalledTransitionTests {
    /// Drives a timer into the issue #87 state: a sleep whose wake never arrives, with the
    /// work countdown running out behind the stuck flag.
    @MainActor
    private func makeStalledState(environment: TestEnvironment) async -> TimerState {
        let state = environment.makeTimerState()
        state.workDurationSecs = 2
        state.restDurationSecs = 5

        state.start()
        environment.workspaceNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await environment.advanceTime(by: 3)
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
        #expect(report.asleepSecs == 3, "The report should measure how long the flag has been stuck.")
    }

    @Test("a sleep whose countdown has not run out is not a stall")
    @MainActor
    func sleepBeforeExpiryIsNotAStall() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 60

        state.start()
        environment.workspaceNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        environment.elapseTimeWithoutTick(by: 30)

        // Sleeping mid-countdown is the routine path: nothing is owed yet, so `handleWake()`
        // still owns the reconciliation and there is nothing to warn about.
        #expect(state.stalledTransition == nil, "A sleep before expiry must not read as a stall.")
    }

    @Test("idle owes no transition, so a stuck flag there is not a stall")
    @MainActor
    func idleNeverStalls() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 1

        state.start()
        state.stop()
        // `stop()` clears the countdown, so the expiry half of the check passes and the
        // mode switch is what has to reject this.
        state.sleptAt = environment.now

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

        #expect(state.awaitingReturn)
        #expect(state.stalledTransition == nil, "The break already finished; nothing is owed.")
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
    func resumingWithoutAStallIsANoOp() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 60

        state.start()
        state.recoverFromStalledTransition()

        #expect(state.mode == .running, "A healthy timer must be left alone.")
        #expect(state.timeRemaining == 60, "Recovery must not disturb a running countdown.")
    }

    @Test("the report URL carries the diagnostics needed to act on it")
    func reportURLCarriesDiagnostics() throws {
        let report = StalledTransitionReport(
            mode: .resting,
            asleepSecs: 900,
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
        #expect(body.contains("15 minutes"), "The stuck duration should read as a duration.")
    }
}
