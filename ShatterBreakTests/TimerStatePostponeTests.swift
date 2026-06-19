import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState postpone behaviors", .tags(.timerState), .timeLimit(.minutes(1)))
struct TimerStatePostponeTests {
    private let postponeDurationSecs = 1.5

    @Test("postpone() transitions state correctly and dismisses overlays")
    @MainActor
    func postponeTransitionsStateAndDismissesOverlays() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(
            overlays: recorder.presenter,
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should enter rest before postponing.")
        #expect(recorder.showCount == 1, "Entering rest should show overlays once before postponing.")

        state.postpone()

        #expect(state.mode == .postponedWork, "postpone() should switch into postponed work mode.")
        #expect(state.isRunning, "Postponed work should run immediately.")
        #expect(state.hasPostponeBeenUsedThisCycle, "Postpone should mark the cycle as used.")
        #expect(state.timeRemaining == postponeDurationSecs, "Postpone should set the postpone timer.")
        #expect(recorder.dismissCount == 1, "Overlays should dismiss when postponing.")
    }

    @Test("postpone() does nothing if conditions not met")
    @MainActor
    func postponeDoesNothingIfConditionsNotMet() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        state.postpone()
        #expect(state.timeRemaining == 1, "Postpone should not change time during work.")

        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting, "The test setup should enter rest before exercising duplicate postpone.")

        state.postpone()
        let postponedTime = state.timeRemaining

        state.postpone()
        #expect(state.mode == .postponedWork, "A duplicate postpone should leave the timer in postponed work.")
        #expect(state.timeRemaining == postponedTime, "A second postpone should be ignored.")
    }

    @Test("postpone timer expires and resumes rest with correct time")
    @MainActor
    func postponeExpiresAndResumesRest() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(
            overlays: recorder.presenter,
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        let originalRestTime = state.timeRemaining

        state.postpone()
        await environment.advanceTime(ticks: 2)

        #expect(state.isResting, "Rest should resume after the postpone work finishes.")
        #expect(state.timeRemaining == originalRestTime, "Rest should resume with the saved time.")
        #expect(recorder.showCount == 2, "Overlays should show again when rest resumes.")
    }

    @Test("hasPostponeBeenUsedThisCycle resets on new rest cycle")
    @MainActor
    func postponeFlagResetsOnNewCycle() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.hasPostponeBeenUsedThisCycle, "Postpone should mark the cycle as used.")

        await environment.advanceTime(ticks: 2)
        #expect(state.isResting, "Postponed work should return to the same rest cycle.")
        #expect(state.hasPostponeBeenUsedThisCycle, "The flag should remain set for the resumed rest.")

        await environment.advanceTime()
        #expect(state.mode == .running, "The resumed rest should eventually advance to work.")

        await environment.advanceTime()
        #expect(state.isResting, "The next cycle should enter rest again.")
        #expect(state.hasPostponeBeenUsedThisCycle == false, "The flag should reset for a new cycle.")
    }

    @Test("pause during postponed work freezes and resumes postponed work")
    @MainActor
    func pauseDuringPostponedWork() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        let snapshot = state.timeRemaining

        state.pause()

        #expect(state.mode == .paused, "Pausing during postponed work should enter paused mode.")
        #expect(state.timeRemaining == snapshot, "Pausing should preserve postponed-work time remaining.")
        #expect(state.canPostpone == false, "The postpone flag should stay set for the cycle.")

        await environment.advanceTime(ticks: 2)
        #expect(state.timeRemaining == snapshot, "The postponed-work timer should stay frozen while paused.")

        state.resume()
        #expect(state.mode == .postponedWork, "Resume should restore the postponed-work phase.")

        await environment.advanceTime(ticks: 2)
        #expect(state.isResting, "After the postponed work finishes, the app should resume rest.")
    }

    @Test("stop during postponed work clears all postpone state")
    @MainActor
    func stopDuringPostponedWork() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        state.postpone()

        state.stop()

        #expect(state.isRunning == false, "stop() should leave postponed work not running.")
        #expect(state.isResting == false, "stop() should clear the resting state during postponed work.")
        #expect(state.hasPostponeBeenUsedThisCycle == false, "Stop should clear the postpone flag.")
        #expect(state.timeRemaining == 0, "stop() should clear time remaining during postponed work.")
    }

    @Test("postpone after some rest has elapsed keeps the saved remainder")
    @MainActor
    func postponeWithPartialRestRemainingPreservesRemainder() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 3

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        await environment.advanceTime()

        #expect(state.isResting, "The test setup should still be resting before postponing.")
        let remainingBeforePostpone = state.timeRemaining
        #expect(remainingBeforePostpone == 2, "One second of rest should have elapsed before postponing.")

        state.postpone()
        await environment.advanceTime(ticks: 2)

        #expect(state.isResting, "Rest should resume after postponing.")
        #expect(state.timeRemaining == remainingBeforePostpone, "The saved remainder should be restored.")
    }

    @Test("rest countdown continues accurately after postpone resumption")
    @MainActor
    func restCountdownAccuracyAfterResume() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()

        await environment.advanceTime(ticks: 2)

        #expect(state.isResting, "Rest should resume after postpone expiry.")
        let resumedRestTime = state.timeRemaining

        await environment.advanceTime()

        #expect(state.timeRemaining == resumedRestTime - 1, "Rest should continue counting down once resumed.")
    }

}
