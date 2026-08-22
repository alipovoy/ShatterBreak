import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState sleep/wake behaviors", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct TimerStateSleepWakeTests {
    @Test("short display sleep never pauses work and continues the countdown")
    @MainActor
    func shortDisplaySleepContinuesWork() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 4

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        // Away for less than a full break, so the work countdown must keep running.
        environment.elapseTimeWithoutTick(by: 2)
        #expect(state.isPaused == false, "Work must never pause on display sleep (issue #4).")

        notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(state.mode == .running, "A short absence should keep the work session running.")
        #expect(state.timeRemaining == 3, "The countdown should reflect the time spent asleep.")

        await environment.advanceTime(ticks: 3)
        #expect(state.isResting, "The timer should still transition to rest after waking.")
    }

    @Test("long sleep during work starts a fresh work session on wake")
    @MainActor
    func longSleepDuringWorkStartsFreshSession() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 3

        state.start()
        await environment.advanceTime(by: 4)
        #expect(state.timeRemaining == 6, "The test setup should consume part of the work period.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away at least one full break, so the absence counts as the break itself.
        environment.elapseTimeWithoutTick(by: 5)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "A long absence should start a fresh work session (issue #69).")
        #expect(state.timeRemaining == 10, "The fresh session should restore the full work duration.")
    }

    @Test("break elapsed while away auto-resumes work when auto-start is on")
    @MainActor
    func breakElapsedWhileAwayAutoResumesWork() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 6) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before simulating sleep.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        environment.elapseTimeWithoutTick(by: 1)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "An elapsed break should auto-resume into work on logon (issue #4).")
        #expect(state.timeRemaining == 5, "Auto-resume should begin a fresh work session.")
    }

    @Test("break elapsed while away awaits the user when auto-start is off")
    @MainActor
    func breakElapsedWhileAwayAwaitsUser() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 5
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 6) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before simulating sleep.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        environment.elapseTimeWithoutTick(by: 1)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.awaitingReturn, "Without auto-start, an elapsed break should await the user on wake.")
        #expect(recorder.dismissCount == 0, "The break overlay should remain visible until the user returns.")
    }

    @Test("short sleep during postponed work continues counting toward rest")
    @MainActor
    func shortSleepDuringPostponedWorkContinues() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: 5)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(state.isPaused == false, "Postponed work must never pause on sleep (issue #4).")

        // Away for less than a full break, so the postponed countdown keeps running.
        environment.elapseTimeWithoutTick(by: 3)

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(state.mode == .postponedWork, "A short absence should keep postponed work running.")
        #expect(state.timeRemaining == 2, "Postponed work should reflect the time spent asleep.")

        await environment.advanceUntil(maxTicks: 3) { state.isResting }
        #expect(state.isResting, "Postponed work should expire back into rest after waking.")
        #expect(state.timeRemaining == 10, "Rest should resume with the saved full duration.")
    }

    @Test("long sleep during postponed work starts a fresh work session on wake")
    @MainActor
    func longSleepDuringPostponedWorkStartsFreshSession() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: 5)
        state.workDurationSecs = 8
        state.restDurationSecs = 3

        state.start()
        await environment.advanceUntil(maxTicks: 9) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")
        #expect(state.canPostpone == false, "Postpone should be spent for this cycle.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away at least one full break, so the absence counts as the break itself.
        environment.elapseTimeWithoutTick(by: 4)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "A long absence should start a fresh work session (issue #69).")
        #expect(state.timeRemaining == 8, "The fresh session should restore the full work duration.")
    }

    @Test("manual pause does not auto-resume on wake")
    @MainActor
    func manualPauseDoesNotAutoResumeOnWake() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 10

        state.start()
        await environment.advanceTime()
        state.pause()
        #expect(state.isPaused, "A user pause should freeze the work countdown.")
        let snapshot = state.timeRemaining

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isPaused, "A manual pause must not auto-resume on wake; only system auto-pauses resume.")
        #expect(
            state.timeRemaining == snapshot,
            "A manual pause should keep its frozen time across a sleep/wake cycle."
        )
    }

    @Test("stopping mid-sleep does not strand the asleep flag into the next cycle")
    @MainActor
    func stopMidSleepDoesNotStrandAsleepFlag() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 5

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Stop lands before the matching wake notification arrives, so `sleptAt` is still set
        // when the cycle resets. It must not survive into the next cycle (issue #87): a leaked
        // flag would silently block every future transition since nothing else ever clears it.
        environment.elapseTimeWithoutTick(by: 2)
        state.stop()
        #expect(state.mode == .idle, "Stop should return to idle even while a sleep is in flight.")

        state.start()
        await environment.advanceUntil(maxTicks: 6) { state.isResting }

        #expect(state.isResting, "A fresh cycle must still transition to rest after a mid-sleep stop.")
    }

    @Test("an expiry landing while asleep defers instead of transitioning")
    @MainActor
    func expiryWhileAsleepDefersUntilWake() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 2
        state.restDurationSecs = 5

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        // Work runs out while the machine is still asleep. The transition is deferred, not
        // dropped: `handleWake()` owns the decision once the time away is known. Issue #87
        // is precisely this deferral never receiving its matching wake.
        await environment.advanceTime(by: 3)
        #expect(state.mode == .running, "An expiry landing while asleep must defer, not transition.")

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(state.isResting, "The deferred transition must resolve once the wake arrives.")
    }

    @Test("parking in awaiting-return never strands the asleep flag")
    @MainActor
    func awaitingReturnDoesNotStrandAsleepFlag() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 4) { state.awaitingReturn }
        #expect(state.awaitingReturn, "Manual mode should park in awaiting-return after the break.")

        // `awaitReturn()` stops sleep/wake observation, so a flag still set here would have
        // no remaining route to being cleared — issue #87's stranding shape. No current path
        // reaches this state with it set; the assertion pins that closed so a future caller
        // cannot reopen it silently (issue #89).
        #expect(state.sleptAt == nil, "Awaiting return must not hold an asleep timestamp.")
    }
}
