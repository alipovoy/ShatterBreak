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
        #expect(spy.showCount == 1)

        state.pause()
        #expect(spy.dismissCount == 2)
        #expect(state.isRunning, "Skip rest should start work.")
        #expect(state.isResting == false)
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
