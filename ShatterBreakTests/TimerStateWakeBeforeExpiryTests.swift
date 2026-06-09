import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState wake before rest expiry", .tags(.timerState, .sleepWake, .overlays))
struct TimerStateWakeBeforeExpiryTests {
    @Test("wake during rest before expiry keeps overlay and rest")
    @MainActor
    func wakeDuringRestBeforeExpiryKeepsState() async {

        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should enter rest before sleep.")
        #expect(spy.showCount == 1, "Entering rest should show the overlay before sleep.")

        await Task.yield()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()

        await environment.advanceTime(by: 0.5)

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()

        #expect(state.isResting, "Rest should continue if it did not expire asleep.")
        #expect(state.timeRemaining > 0, "Rest should keep positive time remaining after waking before expiry.")
        #expect(spy.dismissCount == 0, "Overlay should remain until rest ends.")

    }
}
