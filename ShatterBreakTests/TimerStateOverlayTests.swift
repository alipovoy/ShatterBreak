import Foundation
import Testing

@testable import ShatterBreak

@MainActor
final class OverlaySpy: OverlayManaging {
    private(set) var showCount = 0
    private(set) var dismissCount = 0

    func showOverlays(state: TimerState) {
        showCount += 1
    }

    func dismissOverlays() {
        dismissCount += 1
    }
}

@Suite("TimerState overlay behaviors", .tags(.timerState, .overlays))
struct TimerStateOverlayTests {
    @Test("overlays show when entering rest and dismiss when leaving")
    @MainActor
    func overlaysShowAndDismiss() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime()
        #expect(spy.showCount == 1, "Entering rest should show overlays once.")

        await environment.advanceTime()
        #expect(spy.dismissCount == 2, "Leaving rest should dismiss both managed overlays.")
        #expect(state.isRunning, "Automatic mode should start the next work interval.")
        #expect(state.isResting == false, "Automatic mode should leave rest after rest expires.")
    }

    @Test("pause during rest skips rest and dismisses overlays")
    @MainActor
    func skipRestDismissesOverlay() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(spy.showCount == 1, "Entering rest should show overlays before skipping.")

        state.pause()
        #expect(spy.dismissCount == 2, "Skipping rest should dismiss both managed overlays.")
        #expect(state.isRunning, "Skip rest should start work.")
        #expect(state.isResting == false, "Skip rest should clear the resting state.")
    }

    @Test("manual-start mode keeps overlay and waits for user action")
    @MainActor
    func manualOverlayPersists() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(spy.showCount == 1, "Entering rest should show the manual-mode overlay.")

        await environment.advanceUntil(maxTicks: 2) { state.awaitingReturn }
        #expect(spy.dismissCount == 0, "The overlay should remain visible while waiting.")
        #expect(state.awaitingReturn, "Manual mode should wait for the user to return after rest expires.")

        state.start()
        #expect(spy.dismissCount == 1, "Starting work from awaiting return should dismiss the overlay once.")
    }
}
