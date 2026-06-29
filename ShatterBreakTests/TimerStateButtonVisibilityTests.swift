import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState button visibility", .tags(.timerState), .timeLimit(.minutes(1)))
struct TimerStateButtonVisibilityTests {

    @MainActor
    private func makeRestingState(
        environment: TestEnvironment,
        restDurationSecs: Double
    ) async -> TimerState {
        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = restDurationSecs

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        return state
    }

    // MARK: - Postpone window

    @Test("Postpone is offered at the start of the break and hides once its window elapses")
    @MainActor
    func postponeVisibleInOpeningWindow() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(3.0, forKey: PreferenceKeys.postponeWindowSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        #expect(state.isResting, "Setup should reach the resting phase.")
        #expect(state.showsPostponeButton, "Postpone is offered from the break start.")

        await environment.advanceTime(ticks: 3) // elapsed reaches the 3s window
        #expect(state.showsPostponeButton == false, "Postpone hides once its window has elapsed.")
    }

    @Test("Postpone stays hidden when the feature is disabled")
    @MainActor
    func postponeHiddenWhenDisabled() async {
        let environment = TestEnvironment()
        environment.defaults.set(false, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(600.0, forKey: PreferenceKeys.postponeWindowSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        #expect(state.showsPostponeButton == false, "A disabled Postpone never shows.")
    }

    @Test("Postpone is hidden after it has been used this cycle")
    @MainActor
    func postponeHiddenAfterUse() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(600.0, forKey: PreferenceKeys.postponeWindowSecs)
        environment.defaults.set(1.0, forKey: PreferenceKeys.postponeDurationSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        #expect(state.showsPostponeButton, "Postpone shows before use.")

        state.postpone()
        #expect(state.showsPostponeButton == false, "Postpone hides immediately after use.")

        await environment.advanceTime(ticks: 2) // postpone delay expires, rest resumes
        #expect(state.isResting, "Rest should resume after postponed work.")
        #expect(state.showsPostponeButton == false, "Postpone stays spent for the resumed rest.")
    }

    @Test("Postpone is hidden outside the resting phase")
    @MainActor
    func postponeHiddenWhileWorking() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(600.0, forKey: PreferenceKeys.postponeWindowSecs)

        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 10
        state.start()

        #expect(state.mode == .running, "Setup should be running work.")
        #expect(state.showsPostponeButton == false, "Postpone is only for the resting phase.")
    }

    // MARK: - Early return

    @Test("Early return stays hidden during rest when the feature is disabled")
    @MainActor
    func earlyReturnHiddenWhenDisabled() async {
        let environment = TestEnvironment()
        environment.defaults.set(false, forKey: PreferenceKeys.allowEarlyReturn)
        environment.defaults.set(600.0, forKey: PreferenceKeys.earlyReturnLeadSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        await environment.advanceTime(ticks: 9) // deep into the break
        #expect(state.isResting, "Should still be resting just before the end.")
        #expect(state.showsReturnButton == false, "Disabled early return never shows during rest.")
    }

    @Test("Early return appears in the closing lead window")
    @MainActor
    func earlyReturnVisibleInClosingWindow() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.allowEarlyReturn)
        environment.defaults.set(3.0, forKey: PreferenceKeys.earlyReturnLeadSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        #expect(state.showsReturnButton == false, "Early return is hidden early in the break.")

        await environment.advanceTime(ticks: 7) // remaining reaches the 3s lead
        #expect(state.isResting, "Still resting within the lead window.")
        #expect(state.showsReturnButton, "Early return appears in the closing lead window.")
    }

    @Test("Return button is always shown while awaiting return, regardless of settings")
    @MainActor
    func returnVisibleWhileAwaiting() async {
        let environment = TestEnvironment()
        environment.defaults.set(false, forKey: PreferenceKeys.allowEarlyReturn)
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1
        state.start()
        await environment.advanceUntil(maxTicks: 4) { state.awaitingReturn }

        #expect(state.awaitingReturn, "Manual mode should await the user after rest expires.")
        #expect(state.showsReturnButton, "The return button is required to leave the overlay.")
    }

    // MARK: - Graceful degradation

    @Test("A window longer than the break keeps its button visible the whole break")
    @MainActor
    func oversizedWindowsSpanTheBreak() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(600.0, forKey: PreferenceKeys.postponeWindowSecs)
        environment.defaults.set(true, forKey: PreferenceKeys.allowEarlyReturn)
        environment.defaults.set(600.0, forKey: PreferenceKeys.earlyReturnLeadSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        #expect(state.showsPostponeButton, "An oversized Postpone window shows from the start.")
        #expect(state.showsReturnButton, "An oversized early-return lead shows from the start.")

        await environment.advanceTime(ticks: 9) // remaining 1s, still well inside both windows
        #expect(state.isResting, "Still resting near the end.")
        #expect(state.showsPostponeButton, "Postpone persists across the whole break.")
        #expect(state.showsReturnButton, "Early return persists across the whole break.")
    }

    // MARK: - Configurable postpone delay (live preference)

    @Test("Postpone delay is read live from preferences when no override is supplied")
    @MainActor
    func postponeDelayReadsLivePreference() async {
        let environment = TestEnvironment()
        environment.defaults.set(2.0, forKey: PreferenceKeys.postponeDurationSecs)

        let state = await makeRestingState(environment: environment, restDurationSecs: 10)
        state.postpone()

        #expect(state.mode == .postponedWork, "Postpone should enter postponed work.")
        #expect(state.timeRemaining == 2, "Postpone delay should come from the live preference.")
    }
}
