import AppKit
import Testing

@testable import ShatterBreak

/// The statistics counting rules (issue #10) driven through the full ``TimerState``
/// machine: what counts, and — just as deliberately — what does not.
@Suite("TimerState statistics counting", .tags(.timerState, .statistics), .timeLimit(.minutes(1)))
struct TimerStateStatisticsTests {
    @MainActor
    private func makeTrackedState(
        _ environment: TestEnvironment,
        postponeDurationSecs: Double? = nil
    ) -> TimerState {
        environment.defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        return environment.makeTimerState(postponeDurationSecs: postponeDurationSecs)
    }

    @Test("completed work sessions and breaks count across cycles")
    @MainActor
    func completedCyclesCount() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The work expiry should enter rest.")
        #expect(state.statistics.current.workSessionsCompleted == 1, "A completed work session should count.")
        #expect(state.statistics.current.breaksCompleted == 0, "The break has not completed yet.")

        await environment.advanceTime()
        #expect(state.mode == .running, "Auto mode should start the next work session after the break.")
        #expect(state.statistics.current.breaksCompleted == 1, "A break that ran to completion should count.")

        await environment.advanceTime()
        await environment.advanceTime()
        #expect(state.statistics.current.workSessionsCompleted == 2, "A second cycle should count a second session.")
        #expect(state.statistics.current.breaksCompleted == 2, "A second cycle should count a second break.")
    }

    @Test("stop counts nothing for the interrupted period")
    @MainActor
    func stopCountsNothing() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        state.stop()
        #expect(state.statistics.current.workSessionsCompleted == 0, "Work interrupted by stop should not count.")

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The completed work session should enter rest.")
        state.stop()

        #expect(state.statistics.current.workSessionsCompleted == 1, "The work session completed before the stop.")
        #expect(state.statistics.current.breaksCompleted == 0, "A break interrupted by stop should not count.")
    }

    @Test("skipping the rest does not count the break")
    @MainActor
    func skipRestDoesNotCountBreak() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should be resting before skipping.")

        state.pause()

        #expect(state.mode == .running, "Skipping rest should start the next work session.")
        #expect(state.statistics.current.breaksCompleted == 0, "A skipped break did not complete and should not count.")
    }

    @Test("postpone counts once and the cycle still yields one work session and one break")
    @MainActor
    func postponeCountsOnce() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment, postponeDurationSecs: 1.5)
        state.workDurationSecs = 1
        state.restDurationSecs = 2

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.statistics.current.postponesUsed == 1, "Using Postpone should count.")

        await environment.advanceTime(ticks: 2)
        #expect(state.isResting, "The saved break should resume after the postponed work.")

        await environment.advanceTime(ticks: 2)
        #expect(state.statistics.current.workSessionsCompleted == 1, "A postponed cycle is still one work session.")
        #expect(state.statistics.current.breaksCompleted == 1, "The resumed break should count once it completes.")
        #expect(state.statistics.current.postponesUsed == 1, "The postpone should have counted exactly once.")
    }

    @Test("an early return counts the break as taken plus an early return")
    @MainActor
    func earlyReturnCountsBreakAndEarlyReturn() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should be resting before returning early.")

        state.returnToWork()

        #expect(state.mode == .running, "Returning early should start the next work session.")
        #expect(state.statistics.current.breaksCompleted == 1, "An early return still counts the break as taken.")
        #expect(state.statistics.current.earlyReturns == 1, "The cut-short break should tally an early return.")
    }

    @Test("the routine manual-mode return counts nothing")
    @MainActor
    func routineReturnCountsNothing() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime(ticks: 2)
        #expect(state.awaitingReturn, "Manual mode should park in awaiting-return after the break.")
        #expect(state.statistics.current.breaksCompleted == 1, "The break completed and should count.")

        state.returnToWork()

        #expect(state.isRunning, "The return should start the next work session.")
        #expect(state.statistics.current.earlyReturns == 0, "A return from awaiting-return is not an early return.")
        #expect(state.statistics.current.breaksCompleted == 1, "The routine return should not count another break.")
    }

    @Test("an absence that serves as the break counts neither work nor break")
    @MainActor
    func absenceAsBreakCountsNeither() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 10
        state.restDurationSecs = 3

        state.start()
        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away at least a full break while mid-work: the absence replaces the break.
        environment.elapseTimeWithoutTick(by: 4)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "Auto mode should begin a fresh session after the absence.")
        #expect(state.statistics.current.workSessionsCompleted == 0, "The work countdown never finished.")
        #expect(state.statistics.current.breaksCompleted == 0, "No on-screen break ran.")
    }

    @Test("an absence spilling into the break counts the work session; the resumed break counts on completion")
    @MainActor
    func absenceSpillingIntoBreakCountsWork() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 5
        state.restDurationSecs = 10

        state.start()
        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Longer than the 5s of work left but shorter than a full 10s break: the work
        // countdown ran out during the absence and the break resumes prorated (3s left).
        environment.elapseTimeWithoutTick(by: 7)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "The wake should resume the prorated break.")
        #expect(state.statistics.current.workSessionsCompleted == 1, "The work session completed off-screen.")
        #expect(state.statistics.current.breaksCompleted == 0, "The resumed break has not completed yet.")

        await environment.advanceTime(ticks: 3)
        #expect(state.statistics.current.breaksCompleted == 1, "The resumed break should count once it completes.")
    }

    @Test("a break that elapses fully during sleep counts on wake")
    @MainActor
    func breakElapsedDuringSleepCounts() async {
        let environment = TestEnvironment()
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        await environment.advanceTime()
        #expect(state.isResting, "The test setup should be resting before sleeping.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        environment.elapseTimeWithoutTick(by: 6)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "Auto mode should start work once the slept-through break resolves.")
        #expect(state.statistics.current.breaksCompleted == 1, "The break ran to completion on wall-clock.")
    }

    @Test("opting in resets the tally at the stop→start boundary")
    @MainActor
    func automaticResetOnStartAfterStop() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.resetStatisticsOnStart)
        let state = makeTrackedState(environment)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        await environment.advanceTime()
        #expect(state.statistics.current.workSessionsCompleted == 1, "The tally should accumulate before the stop.")

        state.stop()
        #expect(state.statistics.current.workSessionsCompleted == 1, "Stopping alone should not reset the tally.")

        state.start()
        #expect(state.statistics.current.workSessionsCompleted == 0, "A start from idle should begin a fresh tally.")
    }

    @Test("nothing counts while tracking is disabled")
    @MainActor
    func nothingCountsWhileDisabled() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        await environment.advanceTime(ticks: 2)

        #expect(state.statistics.current.workSessionsCompleted == 0, "Tracking is off, so work should not count.")
        #expect(state.statistics.current.breaksCompleted == 0, "Tracking is off, so breaks should not count.")
    }
}
