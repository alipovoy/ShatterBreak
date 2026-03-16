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

@Suite("TimerState overlay behaviors")
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
        #expect(spy.showCount == 1)

        await environment.advanceTime()
        #expect(spy.dismissCount == 2)
        #expect(state.isRunning)
        #expect(state.isResting == false)
    }

    @Test("pause during rest freezes countdown and resumes without recreating overlay")
    @MainActor
    func pauseDuringRestKeepsOverlayAndResumesRest() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(spy.showCount == 1)

        state.pause()
        let snapshot = state.timeRemaining

        #expect(state.isPaused, "Pausing rest should freeze the countdown.")
        #expect(spy.dismissCount == 0, "Pausing rest should leave the existing overlay in place.")

        await environment.advanceTime(ticks: 2)
        #expect(state.timeRemaining == snapshot, "The rest timer should stay frozen while paused.")

        state.resume()
        #expect(state.isResting, "Resume should return to the interrupted rest phase.")
        #expect(spy.showCount == 1, "Resuming rest should continue the existing overlay without replaying it.")

        await environment.advanceTime()
        #expect(state.timeRemaining == snapshot - 1, "Rest should keep counting down after resume.")
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
        #expect(spy.showCount == 1)

        await environment.advanceUntil(maxTicks: 2) { state.awaitingReturn }
        #expect(spy.dismissCount == 0, "The overlay should remain visible while waiting.")
        #expect(state.awaitingReturn)

        state.start()
        #expect(spy.dismissCount == 1)
    }
}
