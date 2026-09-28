import AppKit
import Testing

@testable import ShatterBreak

/// Failures that must cost a tick, never the session.
@Suite("Timer resilience", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct TimerResilienceTests {
    @Test("the timer still transitions when the boundary timer never fires")
    @MainActor
    func survivesALostBoundaryTimer() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 60

        state.start()
        environment.elapseTimeWithoutTick(by: 45)
        state.reconcile()

        #expect(state.isResting, "A single late reconcile must cross the boundary the timer dropped.")
        #expect(state.timeRemaining == 60, "Time spent at the machine is not break taken, so the break is whole.")
    }

    @Test("the timer still resolves an absence when no notification is ever delivered")
    @MainActor
    func survivesWithoutAnyNotifications() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 600
        state.restDurationSecs = 300

        state.start()
        environment.sleepMachine(by: 3_600)
        state.reconcile()

        #expect(state.mode == .running, "An hour away served as the break (issue #69).")
        #expect(state.timeRemaining == 600, "The session should be fresh, not the stale one from before the sleep.")
    }

    @Test("reconciling repeatedly for the same moment changes nothing")
    @MainActor
    func repeatedReconcilesAreHarmless() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 2
        state.restDurationSecs = 30

        state.start()
        await environment.advanceTime(by: 2)
        #expect(state.isResting, "The setup should have crossed into the break.")

        for _ in 0..<5 {
            state.reconcile()
        }
        state.systemDidWake()

        #expect(state.timeRemaining == 30, "Replayed reconciles must not move the clock.")
        #expect(recorder.showCount == 1, "Nor present the break again.")
        #expect(state.statistics.current.workSessionsCompleted == 1, "Nor bank the same session twice.")
    }

    @Test("a break coming due on a dark screen waits, and the plan does not")
    @MainActor
    func breakWaitsForADisplay() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 2
        state.restDurationSecs = 60

        state.start()
        recorder.hasAwakeScreen = false
        await environment.advanceTime(by: 2)

        #expect(state.isResting, "Time really did pass, so the plan advances even with no screen.")
        #expect(recorder.showCount == 0, "The break must not be presented onto a dark screen.")

        // No notification needed: the next reconcile asks the display again.
        recorder.hasAwakeScreen = true
        await environment.advanceTime(by: 1)

        #expect(recorder.showCount == 1, "The held break should be presented once there is a screen.")
        #expect(state.timeRemaining == 59, "The break kept running while it waited; it is not restarted.")
    }
}

/// A break that happened off-screen is announced settled.
@Suite("Break-end window after a dark screen", .tags(.timerState, .overlays), .timeLimit(.minutes(1)))
struct DarkScreenBreakEndTests {
    @Test("a break that elapsed behind a dark screen is announced settled, not shattered")
    @MainActor
    func breakElapsedBehindADarkScreenIsSettled() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 2
        state.restDurationSecs = 3

        state.start()
        recorder.hasAwakeScreen = false
        await environment.advanceTime(by: 2)
        #expect(state.isResting, "The plan advances with no screen; only the presentation waits.")
        #expect(recorder.showCount == 0, "Nothing is presented onto a dark screen (issues #99, #107).")

        await environment.advanceTime(by: 3)
        #expect(state.awaitingReturn, "Manual mode should park in the break-end window.")

        recorder.hasAwakeScreen = true
        await environment.advanceTime(by: 1)

        #expect(recorder.showCount == 1, "The window the user comes back to is presented once.")
        #expect(
            recorder.lastSettled == true,
            "It announces a break that is already over, so it arrives settled — no shake, no chime."
        )
    }

    @Test("a break dismissed while the screen was dark never surfaces")
    @MainActor
    func breakDismissedBehindADarkScreenNeverSurfaces() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder)
        state.workDurationSecs = 2
        state.restDurationSecs = 3

        state.start()
        recorder.hasAwakeScreen = false
        await environment.advanceTime(by: 2)
        #expect(state.isResting, "The setup needs a break held back from a dark screen.")

        recorder.hasAwakeScreen = true
        await environment.advanceTime(by: 3)

        #expect(state.mode == .running, "Auto mode should have started the next work session.")
        #expect(recorder.showCount == 0, "A break the same reconcile ends must never reach the screen.")
    }
}
