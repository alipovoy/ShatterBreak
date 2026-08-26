import AppKit
import Testing

@testable import ShatterBreak

/// What the rewrite is *for*: the failures that used to end a session now cost a tick.
///
/// Each of these describes a way the old design broke and could not recover — a lost
/// expiry callback, a wake notification that never arrived, a break presented onto a dark
/// screen. None of them needs new machinery to survive here; they survive because nothing
/// is trusted and everything is recomputed.
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
        // Nothing reconciles for well past the boundary: the callback the whole old design
        // hung on simply never arrives. It used to leave the timer at 00:00 until the user
        // noticed and pressed Resume (issues #106, #107).
        environment.elapseTimeWithoutTick(by: 45)
        // The heartbeat, arriving whenever it arrives.
        environment.clock.fireReconcile()

        #expect(state.isResting, "A single late reconcile must cross the boundary the timer dropped.")
        #expect(state.timeRemaining == 60, "Time spent at the machine is not break taken, so the break is whole.")
    }

    @Test("the timer still resolves an absence when no notification is ever delivered")
    @MainActor
    func survivesWithoutAnyNotifications() async {
        let environment = TestEnvironment()
        // A notification centre nothing ever posts to: the app is deaf to sleep and wake.
        let state = environment.makeTimerState()
        state.workDurationSecs = 600
        state.restDurationSecs = 300

        state.start()
        // Wall-clock time passes while the awake-only clock stands still, which is what a
        // sleeping machine does to `ProcessInfo.systemUptime`. That is the evidence, and it
        // cannot go missing the way a notification can (issue #87).
        environment.sleepMachine(by: 3_600)
        environment.clock.fireReconcile()

        #expect(state.mode == .running, "An hour away served as the break (issue #69).")
        #expect(state.timeRemaining == 600, "The session should be fresh, not the stale one from before the sleep.")
    }

    @Test("reconciling repeatedly for the same moment changes nothing")
    @MainActor
    func repeatedReconcilesAreHarmless() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 2
        state.restDurationSecs = 30

        state.start()
        await environment.advanceTime(by: 2)
        #expect(state.isResting, "The setup should have crossed into the break.")

        // The boundary timer, the heartbeat and a wake notification all landing within
        // milliseconds of each other is the normal case, not a corner case.
        for _ in 0..<5 {
            environment.clock.fireReconcile()
        }
        environment.workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.timeRemaining == 30, "Replayed reconciles must not move the clock.")
        #expect(recorder.showCount == 1, "Nor present the break again.")
        #expect(state.statistics.current.workSessionsCompleted == 1, "Nor bank the same session twice.")
    }

    @Test("a break coming due on a dark screen waits, and the plan does not")
    @MainActor
    func breakWaitsForADisplay() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 2
        state.restDurationSecs = 60

        state.start()
        // macOS wakes to service background work with the display still off. Shattering
        // there spends the break against a screen nobody is looking at, which is why
        // automatic recovery was rejected in the #99 and #107 reviews.
        environment.isDisplayAwake = false
        await environment.advanceTime(by: 2)

        #expect(state.isResting, "Time really did pass, so the plan advances even with no screen.")
        #expect(recorder.showCount == 0, "The break must not be presented onto a dark screen.")

        // No notification needed: the next reconcile asks the display again.
        environment.isDisplayAwake = true
        await environment.advanceTime(by: 1)

        #expect(recorder.showCount == 1, "The held break should be presented once there is a screen.")
        #expect(state.timeRemaining == 59, "The break kept running while it waited; it is not restarted.")
    }

    @Test("the clock is asked for nothing while the timer is idle")
    @MainActor
    func idleSchedulesNothing() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5

        state.start()
        #expect(environment.clock.scheduledBoundary == 5, "A running countdown arms a timer for exactly its length.")
        #expect(environment.clock.heartbeatRequested, "And a heartbeat behind it, in case that timer goes missing.")

        state.stop()
        #expect(environment.clock.scheduledBoundary == nil, "A stopped timer has no boundary to wait for.")
        #expect(
            environment.clock.heartbeatRequested == false,
            "An idle app should schedule nothing at all: the safety net costs energy and guards nothing here."
        )
    }
}
