import Foundation
import Testing

@testable import ShatterBreak

@Suite("TimerState overlay behaviors", .tags(.timerState, .overlays), .timeLimit(.minutes(1)))
struct TimerStateOverlayTests {
    @Test("starting work prepares the overlay before the break needs it")
    @MainActor
    func startPreparesOverlayPermissions() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await recorder.prepared(1)

        #expect(
            recorder.prepareCount == 1,
            """
            Screen-capture consent has to be settled at the head of the work session; \
            asking once the overlay is up is the ambush issue #90 is about.
            """
        )
        #expect(recorder.showCount == 0, "Preparing must not present anything on its own.")
    }

    @Test("every work session prepares again, so a lapsed consent is caught before the break")
    @MainActor
    func eachWorkSessionPreparesAgain() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime()
        await environment.advanceTime()
        await recorder.prepared(2)

        #expect(state.isRunning && state.isResting == false, "Automatic mode should begin a second work session.")
        #expect(
            recorder.prepareCount == 2,
            "The consent expires roughly monthly, so each work session re-settles it rather than trusting a cache."
        )
    }

    @Test("overlays show when entering rest and dismiss when leaving")
    @MainActor
    func overlaysShowAndDismiss() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime()
        #expect(recorder.showCount == 1, "Entering rest should show overlays once.")

        await environment.advanceTime()
        #expect(recorder.dismissCount == 1, "Leaving rest should dismiss overlays once.")
        #expect(state.isRunning, "Automatic mode should start the next work interval.")
        #expect(state.isResting == false, "Automatic mode should leave rest after rest expires.")
    }

    @Test("pause during rest skips rest and dismisses overlays")
    @MainActor
    func skipRestDismissesOverlay() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(recorder.showCount == 1, "Entering rest should show overlays before skipping.")

        state.pause()
        #expect(recorder.dismissCount == 1, "Skipping rest should dismiss overlays once.")
        #expect(state.isRunning, "Skip rest should start work.")
        #expect(state.isResting == false, "Skip rest should clear the resting state.")
    }

    @Test("manual-start mode keeps overlay and waits for user action")
    @MainActor
    func manualOverlayPersists() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(recorder.showCount == 1, "Entering rest should show the manual-mode overlay.")

        await environment.advanceUntil(maxTicks: 2) { state.awaitingReturn }
        #expect(recorder.dismissCount == 0, "The overlay should remain visible while waiting.")
        #expect(recorder.showCount == 1, "The break on screen is settled in place, not presented again.")
        #expect(state.awaitingReturn, "Manual mode should wait for the user to return after rest expires.")

        state.start()
        #expect(recorder.dismissCount == 1, "Starting work from awaiting return should dismiss the overlay once.")
    }

    @Test("the DarkWake gate asks the overlay presenter")
    @MainActor
    func gateAsksTheOverlayPresenter() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        recorder.hasAwakeScreen = false
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime()

        #expect(state.isResting, "The plan advances regardless of the screen.")
        #expect(recorder.showCount == 0, "No awake screen to draw on, so the break must wait.")

        recorder.hasAwakeScreen = true
        state.reconcile()

        #expect(recorder.showCount == 1, "Once a screen the presenter would draw on is lit, the held break shows.")
    }

    @Test("a stop that lands on an unreconciled boundary never puts the break on screen")
    @MainActor
    func stopAcrossAMissedBoundaryPresentsNothing() {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 60
        state.restDurationSecs = 60

        state.start()
        environment.elapseTimeWithoutTick(by: 61)
        state.stop()

        #expect(recorder.showCount == 0, "A break built and torn down in one turn is work spent on nothing.")
        #expect(state.isRunning == false)
    }

    @Test("a stop on a display that just woke never flushes the break it is dismissing")
    @MainActor
    func stopOnAWokenDisplayDoesNotFlushTheHeldBreak() {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 60
        state.restDurationSecs = 60

        recorder.hasAwakeScreen = false
        state.start()
        environment.clock.elapse(by: 61)
        state.reconcile()
        #expect(recorder.showCount == 0, "A dark display holds the break back.")

        recorder.hasAwakeScreen = true
        state.stop()

        #expect(recorder.showCount == 0, "The dismissal must land before the retry does (issue #112).")
        #expect(state.isRunning == false)
    }
}
