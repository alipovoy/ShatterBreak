import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState wake before rest expiry", .tags(.timerState, .sleepWake, .overlays), .timeLimit(.minutes(1)))
struct TimerStateWakeBeforeExpiryTests {
    @Test("wake during rest before expiry keeps overlay and rest")
    @MainActor
    func wakeDuringRestBeforeExpiryKeepsState() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should enter rest before sleep.")
        #expect(recorder.showCount == 1, "Entering rest should show the overlay before sleep.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        await environment.advanceTime(by: 0.5)

        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "Rest should continue if it did not expire asleep.")
        #expect(state.timeRemaining > 0, "Rest should keep positive time remaining after waking before expiry.")
        #expect(recorder.dismissCount == 0, "Overlay should remain until rest ends.")
    }
}
