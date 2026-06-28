import AppKit
import Testing

@testable import ShatterBreak

/// Verifies that ``TimerState`` reads its preferences defensively: a corrupt or
/// unrecognized stored value must fall back to ``PreferenceDefaults`` rather than
/// changing behavior or crashing.
@Suite("TimerState preference fallbacks", .tags(.timerState), .timeLimit(.minutes(1)))
struct TimerStatePreferenceTests {
    @Test("a corrupt work-start preference falls back to the automatic default")
    @MainActor
    func corruptWorkStartModeFallsBackToAutomatic() async {
        let environment = TestEnvironment()
        // A garbage string simulates a corrupt or unrecognized stored preference.
        environment.defaults.set("garbage", forKey: PreferenceKeys.workStartMode)

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

        #expect(
            state.mode == .running,
            "A corrupt work-start preference must use the automatic default and auto-resume work."
        )
    }
}
