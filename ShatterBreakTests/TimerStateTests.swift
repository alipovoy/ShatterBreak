import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState basic flows")
struct TimerStateBasicTests {
    @Test("start() initializes and transitions to rest")
    @MainActor
    func startTransitionsToRest() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 2

        state.start()
        #expect(state.isRunning)
        #expect(state.isPaused == false)
        #expect(state.isResting == false)
        #expect(state.timeRemaining == 1)

        await environment.advanceTime()

        #expect(state.isResting, "Should enter rest after work completes.")
        #expect(state.isRunning)
        #expect(state.timeRemaining == 2, "Rest should start with the configured duration.")
    }

    @Test("pause during work freezes countdown; resume continues")
    @MainActor
    func pauseAndResume() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        await environment.advanceTime()
        state.pause()
        let snapshot = state.timeRemaining

        #expect(state.isPaused)
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
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 3
        
        state.start()
        await environment.advanceTime(by: 0.5)
        #expect(state.timeRemaining == 2.5)
        
        await environment.advanceTime(by: 1.5)
        #expect(state.timeRemaining == 1)
    }

    @Test("stop() cancels and resets state")
    @MainActor
    func stopResets() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        state.stop()

        #expect(state.isRunning == false)
        #expect(state.mode == .idle)
        #expect(state.timeRemaining == 0)
    }

    @Test("manual mode waits for user after rest expiry")
    @MainActor
    func manualModeDelaysWorkStart() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 3) { state.awaitingReturn }

        #expect(state.isRunning == false, "Work should not auto-start in manual mode.")
        #expect(state.awaitingReturn)
        #expect(state.timeRemaining == 0)

        state.start()
        #expect(state.isRunning)
        #expect(state.awaitingReturn == false)
    }

    @Test("formatting helper produces zero-padded strings")
    @MainActor
    func formattingProducesCorrectOutput() {
        #expect(TimerState.format(timeInterval: 0) == "00:00")
        #expect(TimerState.format(timeInterval: 5) == "00:05")
        #expect(TimerState.format(timeInterval: 65) == "01:05")
        #expect(TimerState.format(timeInterval: 599) == "09:59")
        #expect(TimerState.format(timeInterval: 600) == "10:00")
        #expect(TimerState.format(timeInterval: 8.999) == "00:09")
        #expect(TimerState.format(timeInterval: 0.1) == "00:01")
    }

    @Test("visibility flag reflects each timer mode")
    @MainActor
    func visibilityFlagRespectsState() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())

        state.mode = .awaitingReturn
        #expect(state.shouldShowTimeInMenuBar == false)

        state.mode = .idle
        #expect(state.shouldShowTimeInMenuBar == false)

        state.mode = .running
        #expect(state.shouldShowTimeInMenuBar)

        state.mode = .paused
        #expect(state.shouldShowTimeInMenuBar)

        state.mode = .postponedWork
        #expect(state.shouldShowTimeInMenuBar)

        state.mode = .resting
        #expect(state.shouldShowTimeInMenuBar == false)
    }

    @Test("duration editing is only available while inactive")
    @MainActor
    func durationEditingIsOnlyAvailableWhileInactive() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())

        state.mode = .idle
        #expect(state.canEditDurations)

        state.mode = .running
        #expect(state.canEditDurations == false)

        state.mode = .paused
        #expect(state.canEditDurations == false)

        state.mode = .resting
        #expect(state.canEditDurations == false)

        state.mode = .postponedWork
        #expect(state.canEditDurations == false)

        state.mode = .awaitingReturn
        #expect(state.canEditDurations == false)
    }

    @Test("formattedTimeRemaining still produces string regardless of state")
    @MainActor
    func formattingUnaffectedByState() {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.timeRemaining = 75
        #expect(state.formattedTimeRemaining == "01:15")

        state.mode = .running
        state.mode = .resting
        #expect(state.formattedTimeRemaining == "01:15")
    }

    @Test("initialization loads stored durations and falls back for zero values")
    @MainActor
    func initializationLoadsStoredDurations() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(120.0, forKey: PreferenceKeys.workDurationSecs)
        defaults.set(0.0, forKey: PreferenceKeys.restDurationSecs)

        let state = environment.makeTimerState(overlayManager: OverlaySpy())

        #expect(state.workDurationSecs == 120)
        #expect(state.restDurationSecs == 300)
    }

    @Test("timer state deallocates while sleep observers are idle")
    @MainActor
    func timerStateDeallocatesWhileObservingSleepNotifications() async {
        let environment = TestEnvironment()
        weak var weakState: TimerState?

        do {
            let state = environment.makeTimerState(overlayManager: OverlaySpy())
            weakState = state
            await Task.yield()
        }

        await Task.yield()
        #expect(weakState == nil)
    }
}

@Suite("TimerState sleep/wake behaviors")
struct TimerStateSleepWakeTests {
    @Test("display sleep auto-pauses work; wake auto-resumes")
    @MainActor
    func displaySleepAutoPauseAndResume() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 3
        state.restDurationSecs = 2

        await Task.yield()
        state.start()
        await Task.yield()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await Task.yield()
        #expect(state.isPaused, "Work should auto-pause on display sleep.")

        notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        await Task.yield()
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

        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting)

        await Task.yield()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()

        await environment.advanceTime()

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        #expect(state.isRunning == false, "The app should be idle after waking from an expired rest.")
        #expect(state.isResting == false, "Rest should be cleared after wake when it expired asleep.")
        #expect(state.mode == .idle)
    }
    
    @Test("wake during rest handles elapsed wall-clock time without needing a tick")
    @MainActor
    func wakeFromRestDoesNotNeedManualTick() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)
        
        let state = environment.makeTimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 1
        
        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting)
        
        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()
        
        environment.elapseTimeWithoutTick(by: 1)
        
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        
        #expect(state.mode == .idle)
        #expect(state.isRunning == false)
        #expect(state.isResting == false)
    }
}
