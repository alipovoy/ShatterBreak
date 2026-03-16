import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState postpone behaviors")
struct TimerStatePostponeTests {
    private let postponeDurationSecs = 1.5

    @Test("canPostpone returns true when resting and not used this cycle")
    @MainActor
    func canPostponeTrueWhenRestingAndNotUsed() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()

        #expect(state.isResting)
        #expect(state.hasPostponeBeenUsedThisCycle == false)
        #expect(state.canPostpone, "Postpone should be available during a fresh rest.")
    }

    @Test("canPostpone returns false when not resting")
    @MainActor
    func canPostponeFalseWhenNotResting() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        #expect(state.isResting == false)
        #expect(state.canPostpone == false, "Postpone should not be available during work.")

        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting)

        state.postpone()
        #expect(state.isResting == false)
        #expect(state.canPostpone == false, "Postpone should not remain available in postponed work.")
    }

    @Test("canPostpone returns false when already used this cycle")
    @MainActor
    func canPostponeFalseWhenAlreadyUsed() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.canPostpone)

        state.postpone()
        #expect(state.hasPostponeBeenUsedThisCycle)
        #expect(state.canPostpone == false, "Postpone should only be allowed once per cycle.")

        await environment.advanceTime(ticks: 2)

        #expect(state.isResting)
        #expect(state.canPostpone == false, "Postpone should stay unavailable until the next cycle.")
    }

    @Test("postpone() transitions state correctly and dismisses overlays")
    @MainActor
    func postponeTransitionsStateAndDismissesOverlays() async {
        let environment = TestEnvironment()
        let spy = OverlaySpy()
        let state = environment.makeTimerState(
            overlayManager: spy,
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.isResting)
        #expect(spy.showCount == 1)

        state.postpone()

        #expect(state.mode == .postponedWork)
        #expect(state.isRunning)
        #expect(state.hasPostponeBeenUsedThisCycle, "Postpone should mark the cycle as used.")
        #expect(state.timeRemaining == postponeDurationSecs, "Postpone should set the postpone timer.")
        #expect(spy.dismissCount == 1, "Overlays should dismiss when postponing.")
    }

    @Test("postpone() does nothing if conditions not met")
    @MainActor
    func postponeDoesNothingIfConditionsNotMet() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        state.postpone()
        #expect(state.timeRemaining == 1, "Postpone should not change time during work.")

        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        #expect(state.isResting)

        state.postpone()
        let postponedTime = state.timeRemaining

        state.postpone()
        #expect(state.mode == .postponedWork)
        #expect(state.timeRemaining == postponedTime, "A second postpone should be ignored.")
    }

    @Test("postpone timer expires and resumes rest with correct time")
    @MainActor
    func postponeExpiresAndResumesRest() async {
        let environment = TestEnvironment()
        let spy = OverlaySpy()
        let state = environment.makeTimerState(
            overlayManager: spy,
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
        #expect(spy.showCount == 2, "Overlays should show again when rest resumes.")
    }

    @Test("hasPostponeBeenUsedThisCycle resets on new rest cycle")
    @MainActor
    func postponeFlagResetsOnNewCycle() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.hasPostponeBeenUsedThisCycle)

        await environment.advanceTime(ticks: 2)
        #expect(state.isResting)
        #expect(state.hasPostponeBeenUsedThisCycle, "The flag should remain set for the resumed rest.")

        await environment.advanceTime()
        #expect(state.mode == .running)

        await environment.advanceTime()
        #expect(state.isResting, "The next cycle should enter rest again.")
        #expect(state.hasPostponeBeenUsedThisCycle == false, "The flag should reset for a new cycle.")
    }

    @Test("pause during postponed work freezes and resumes postponed work")
    @MainActor
    func pauseDuringPostponedWork() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        let snapshot = state.timeRemaining

        state.pause()

        #expect(state.mode == .paused)
        #expect(state.timeRemaining == snapshot)
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
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        state.postpone()

        state.stop()

        #expect(state.isRunning == false)
        #expect(state.isResting == false)
        #expect(state.hasPostponeBeenUsedThisCycle == false, "Stop should clear the postpone flag.")
        #expect(state.timeRemaining == 0)
    }

    @Test("early postpone preserves rest time")
    @MainActor
    func earlyPostponePreservesRestTime() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()

        let restTimeWhenPostponed = state.timeRemaining
        #expect(restTimeWhenPostponed == 10)

        state.postpone()
        await environment.advanceTime(ticks: 2)

        #expect(state.isResting, "Postpone should expire back into rest.")
        #expect(state.timeRemaining == restTimeWhenPostponed, "Saved rest time should be preserved.")
    }

    @Test("postpone after some rest has elapsed keeps the saved remainder")
    @MainActor
    func postponeWithPartialRestRemainingPreservesRemainder() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
        state.workDurationSecs = 1
        state.restDurationSecs = 3

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        await environment.advanceTime()

        #expect(state.isResting)
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
        let state = environment.makeTimerState(
            overlayManager: OverlaySpy(),
            postponeDurationSecs: postponeDurationSecs
        )
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
