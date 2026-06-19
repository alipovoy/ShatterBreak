import Foundation
import Testing

@testable import ShatterBreak

@Suite("TimerState overlay behaviors", .tags(.timerState, .overlays), .timeLimit(.minutes(1)))
struct TimerStateOverlayTests {
    @Test("overlays show when entering rest and dismiss when leaving")
    @MainActor
    func overlaysShowAndDismiss() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
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
        let state = environment.makeTimerState(overlays: recorder.presenter)
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
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(recorder.showCount == 1, "Entering rest should show the manual-mode overlay.")

        await environment.advanceUntil(maxTicks: 2) { state.awaitingReturn }
        #expect(recorder.dismissCount == 0, "The overlay should remain visible while waiting.")
        #expect(state.awaitingReturn, "Manual mode should wait for the user to return after rest expires.")

        state.start()
        #expect(recorder.dismissCount == 1, "Starting work from awaiting return should dismiss the overlay once.")
    }
}
