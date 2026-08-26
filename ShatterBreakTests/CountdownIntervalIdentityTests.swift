import AppKit
import Testing

@testable import ShatterBreak

/// A new countdown interval must be visible to anything rendering the clock.
///
/// The menu-bar label drives its own per-second refresh in a task that ends when the
/// countdown reaches zero, and only a change in the task's key revives it. Keying that on
/// `mode` alone was not enough: work auto-resuming after an absence that stood in for the
/// break leaves the mode at `.running`, so the label kept the finished interval's last
/// frame on screen while the state machine counted down a fresh session (issue #108).
@Suite("Countdown interval identity", .tags(.timerState, .sleepWake), .timeLimit(.minutes(1)))
struct CountdownIntervalIdentityTests {
    @Test("a fresh session on wake changes the countdown identity even in the same mode")
    @MainActor
    func freshSessionOnWakeChangesIdentity() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 3

        state.start()
        await environment.advanceTime(by: 4)
        let identityBeforeSleep = state.countdownIntervalID

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away for longer than a full break, so the absence counts as the break and work
        // starts over — the exact transition that leaves `mode` untouched.
        environment.elapseTimeWithoutTick(by: 30)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "The scenario needs work running on both sides of the sleep.")
        #expect(
            state.countdownIntervalID != identityBeforeSleep,
            "A fresh work session must be a new interval, or the visible clock never restarts."
        )
    }

    @Test("beginning an interval notifies observers of the remaining time")
    @MainActor
    func beginningIntervalNotifiesObservers() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 10

        let observation = ObservationFlag()
        withObservationTracking {
            _ = state.timeRemaining
        } onChange: {
            observation.fired = true
        }

        state.start()

        #expect(
            observation.fired,
            "The plan must be observable, or a view reading the clock cannot know it moved."
        )
    }

    @Test("every phase of a cycle is a distinct interval")
    @MainActor
    func everyPhaseIsADistinctInterval() async {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)
        let state = environment.makeTimerState()
        state.workDurationSecs = 2
        state.restDurationSecs = 2

        state.start()
        let work = state.countdownIntervalID

        await environment.advanceTime(by: 2)
        #expect(state.isResting, "The work session should hand over to the break.")
        let rest = state.countdownIntervalID

        await environment.advanceTime(by: 2)
        #expect(state.mode == .running, "Auto-start should begin the next work session.")
        let nextWork = state.countdownIntervalID

        #expect(work != rest, "The break is not the work session it followed.")
        #expect(rest != nextWork, "The next work session is not the break it followed.")
        #expect(work != nextWork, "Back-to-back work sessions must not share an identity.")
    }
}

/// A reference box so `withObservationTracking`'s sendable change handler can report back.
private final class ObservationFlag: @unchecked Sendable {
    var fired = false
}
