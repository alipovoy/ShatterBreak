import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState basic flows", .tags(.timerState), .timeLimit(.minutes(1)))
struct TimerStateBasicTests {
    @Test("start() initializes and transitions to rest")
    @MainActor
    func startTransitionsToRest() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 2

        state.start()
        #expect(state.isRunning, "start() should put the timer into a running work interval.")
        #expect(state.isPaused == false, "A newly started timer should not be paused.")
        #expect(state.isResting == false, "A newly started timer should begin with work, not rest.")
        #expect(state.timeRemaining == 1, "Work should start with the configured duration.")

        await environment.advanceTime()

        #expect(state.isResting, "Should enter rest after work completes.")
        #expect(state.isRunning, "The timer should keep running after transitioning to rest.")
        #expect(state.timeRemaining == 2, "Rest should start with the configured duration.")
    }

    @Test("pause during work freezes countdown; resume continues")
    @MainActor
    func pauseAndResume() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        await environment.advanceTime()
        state.pause()
        let snapshot = state.timeRemaining

        #expect(state.isPaused, "pause() should move the timer into a paused state.")
        await environment.advanceTime(ticks: 2)
        #expect(state.timeRemaining == snapshot, "timeRemaining should not change while paused.")

        state.resume()
        await environment.advanceTime()

        #expect(state.timeRemaining == snapshot - 1, "timeRemaining should resume decreasing.")
    }

    @Test("work countdown tracks elapsed time")
    @MainActor
    func workCountdownTracksElapsedTime() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 3

        state.start()
        await environment.advanceTime(by: 0.5)
        #expect(state.timeRemaining == 2.5, "Half a second of elapsed time should reduce the work countdown.")

        await environment.advanceTime(by: 1.5)
        #expect(state.timeRemaining == 1, "Additional elapsed time should continue reducing the work countdown.")
    }

    @Test("work countdown reflects elapsed time without model ticks")
    @MainActor
    func workCountdownReflectsElapsedTimeWithoutTick() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 3

        state.start()
        environment.elapseTimeWithoutTick(by: 1.5)

        #expect(state.timeRemaining == 1.5, "Reading timeRemaining should account for elapsed time even before a tick.")
    }

    @Test("stop() cancels and resets state")
    @MainActor
    func stopResets() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        state.stop()

        #expect(state.isRunning == false, "stop() should leave the timer not running.")
        #expect(state.mode == .idle, "stop() should reset the mode to idle.")
        #expect(state.timeRemaining == 0, "stop() should clear remaining time.")
    }

    @Test("manual mode waits for user after rest expiry")
    @MainActor
    func manualModeDelaysWorkStart() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 3) { state.awaitingReturn }

        #expect(state.isRunning == false, "Work should not auto-start in manual mode.")
        #expect(state.awaitingReturn, "Manual mode should wait for user return after rest expires.")
        #expect(state.timeRemaining == 0, "Expired manual rest should have no remaining time.")

        state.start()
        #expect(state.isRunning, "Starting from awaiting return should begin work.")
        #expect(state.awaitingReturn == false, "Starting from awaiting return should clear the waiting state.")
    }

    @Test("autoStartIfEnabled() starts work when the launch preference is on")
    @MainActor
    func autoStartLaunchEnabledStartsWork() {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.autoStartOnLaunch)

        let state = environment.makeTimerState()
        state.autoStartIfEnabled()

        #expect(state.isRunning, "Auto-start on launch should begin a work session when enabled.")
        #expect(state.mode == .running, "Auto-start should put the timer into the running work state.")
    }

    @Test("autoStartIfEnabled() does nothing when the launch preference is off")
    @MainActor
    func autoStartLaunchDisabledStaysIdle() {
        let environment = TestEnvironment()
        // Default is off; leave the preference unset to exercise the fallback.
        let state = environment.makeTimerState()
        state.autoStartIfEnabled()

        #expect(state.mode == .idle, "Auto-start should leave the timer idle when the preference is off.")
        #expect(state.isRunning == false, "A disabled launch preference should not start the timer.")
    }

    @Test("autoStartIfEnabled() does not disrupt an already-running timer")
    @MainActor
    func autoStartLaunchIgnoredWhenNotIdle() {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.autoStartOnLaunch)

        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.start()
        let snapshot = state.timeRemaining

        state.autoStartIfEnabled()

        #expect(state.mode == .running, "Auto-start should not change the mode of an active timer.")
        #expect(state.timeRemaining == snapshot, "Auto-start should not restart an already-running work session.")
    }

    @Test("formatting helper produces zero-padded strings")
    @MainActor
    func formattingProducesCorrectOutput() {
        #expect(TimerState.format(timeInterval: 0) == "00:00", "Zero seconds should format as 00:00.")
        #expect(TimerState.format(timeInterval: 5) == "00:05", "Single-digit seconds should be zero padded.")
        #expect(TimerState.format(timeInterval: 65) == "01:05", "Minutes and seconds should be zero padded.")
        #expect(TimerState.format(timeInterval: 599) == "09:59", "Single-digit minutes should be zero padded.")
        #expect(
            TimerState.format(timeInterval: 600) == "10:00",
            "Double-digit minutes should format without truncation."
        )
        #expect(TimerState.format(timeInterval: 8.999) == "00:09", "Fractional seconds should round up for display.")
        #expect(
            TimerState.format(timeInterval: 0.1) == "00:01",
            "Subsecond positive values should display at least one second."
        )
    }

    @Test("initialization loads stored durations and falls back for zero values")
    @MainActor
    func initializationLoadsStoredDurations() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(120.0, forKey: PreferenceKeys.workDurationSecs)
        defaults.set(0.0, forKey: PreferenceKeys.restDurationSecs)

        let state = environment.makeTimerState()

        #expect(state.workDurationSecs == 120, "Initialization should load a stored work duration.")
        #expect(state.restDurationSecs == 300, "Initialization should fall back when stored rest duration is zero.")
    }

    @Test("timer state deallocates while sleep observers are active")
    @MainActor
    func timerStateDeallocatesWhileObservingSleepNotifications() async {
        let environment = TestEnvironment()
        weak var weakState: TimerState?

        do {
            let state = environment.makeTimerState()
            state.workDurationSecs = 60
            // `start()` activates the workspace sleep/wake observers, so this exercises
            // the weak-capture path of the observer blocks (and the tick handler), not
            // just a never-started object.
            state.start()
            #expect(state.isRunning, "start() should activate the sleep observers under test.")
            weakState = state
        }

        await Task.yield()
        #expect(
            weakState == nil,
            "TimerState should deallocate even while its sleep observers are active."
        )
    }
}

@Suite("TimerState sleep/wake behaviors", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct TimerStateSleepWakeTests {
    @Test("display sleep auto-pauses work; wake auto-resumes")
    @MainActor
    func displaySleepAutoPauseAndResume() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 3
        state.restDurationSecs = 2

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(state.isPaused, "Work should auto-pause on display sleep.")

        notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        #expect(state.isPaused == false, "Work should auto-resume on display wake.")

        await environment.advanceTime(ticks: 3)
        #expect(state.isResting, "The timer should still transition to rest after resume.")
    }

    @Test("rest expires while system is asleep returns to idle on wake")
    @MainActor
    func restExpiresWhileAwayReturnsIdle() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before simulating sleep.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        await environment.advanceTime()

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isRunning == false, "The app should be idle after waking from an expired rest.")
        #expect(state.isResting == false, "Rest should be cleared after wake when it expired asleep.")
        #expect(state.mode == .idle, "The timer mode should be idle after waking from an expired rest.")
    }

    @Test("wake during rest handles elapsed wall-clock time without needing a tick")
    @MainActor
    func wakeFromRestDoesNotNeedManualTick() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before simulating sleep.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        environment.elapseTimeWithoutTick(by: 1)

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .idle, "Wake should resolve expired rest to idle without a manual tick.")
        #expect(state.isRunning == false, "Wake after expired rest should not keep the timer running.")
        #expect(state.isResting == false, "Wake after expired rest should clear the resting state.")
    }

    @Test("system sleep auto-pauses postponed work; wake restores and resumes it")
    @MainActor
    func sleepAutoPausesPostponedWorkAndWakeRestoresIt() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: 5)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before postponing.")

        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")
        let postponedRemaining = state.timeRemaining

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(state.isPaused, "System sleep should auto-pause postponed work.")
        #expect(
            state.timeRemaining == postponedRemaining,
            "Sleep should freeze the postponed-work countdown."
        )

        // Wall-clock time passes while asleep, but the frozen countdown must not advance.
        environment.elapseTimeWithoutTick(by: 3)

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(state.mode == .postponedWork, "Wake should restore postponed work after a system auto-pause.")
        #expect(
            state.timeRemaining == postponedRemaining,
            "Resumed postponed work should keep its frozen remaining time."
        )

        await environment.advanceTime(ticks: 5)
        #expect(state.isResting, "Postponed work should expire back into rest after waking.")
        #expect(state.timeRemaining == 10, "Rest should resume with the saved full duration.")
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
}
