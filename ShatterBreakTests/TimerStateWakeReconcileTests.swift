import AppKit
import Testing

@testable import ShatterBreak

/// End-to-end coverage for the wake reconciliation that crosses or replaces a break,
/// complementing the pure ``WakeOutcome`` unit tests. Drives the full ``TimerState``
/// machine through sleep/wake notifications (issues #69, #72).
@Suite("TimerState wake reconciliation", .tags(.timerState, .sleepWake, .overlays), .timeLimit(.minutes(1)))
struct TimerStateWakeReconcileTests {
    @Test("absence crossing into the break resumes the prorated remainder")
    @MainActor
    func absenceCrossingIntoBreakResumesProratedRemainder() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 5
        state.restDurationSecs = 10

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away longer than the 5s of work left but less than a full 10s break: work is
        // consumed and the whole 7s away is credited as rest, leaving 10 - 7 = 3s.
        environment.elapseTimeWithoutTick(by: 7)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "Crossing into the break on wake should enter the rest phase.")
        #expect(state.timeRemaining == 3, "The break should resume with the whole away time credited as rest.")
        #expect(recorder.showCount == 1, "Crossing into the break should present the break overlay.")
    }

    @Test("long absence during work awaits the user in manual mode")
    @MainActor
    func longAbsenceDuringWorkAwaitsUserInManualMode() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 10
        state.restDurationSecs = 3

        state.start()

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away at least a full break, so the absence is the break itself — but manual
        // mode must not silently start a new work session (issue #69).
        environment.elapseTimeWithoutTick(by: 4)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.awaitingReturn, "Manual mode should wait for the user after a long absence during work.")
        #expect(state.isRunning == false, "Work must not silently restart in manual mode.")
        #expect(recorder.showCount == 1, "The break-end window should be presented for the user to start work.")

        state.start()
        #expect(state.isRunning, "Starting from the break-end window should begin a fresh work session.")
        #expect(state.timeRemaining == 10, "The fresh session should restore the full work duration.")
    }

    @Test("absence crossing into a postponed break resumes the prorated saved rest")
    @MainActor
    func absenceCrossingIntoPostponedBreakResumesProratedRemainder() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState(postponeDurationSecs: 5)
        state.workDurationSecs = 1
        state.restDurationSecs = 8

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away 6s: longer than the 5s of postpone work, shorter than the 8s saved rest,
        // so the saved break resumes with 8 - 6 = 2s, crediting the whole absence.
        environment.elapseTimeWithoutTick(by: 6)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "Crossing into the saved break should re-enter rest.")
        #expect(state.timeRemaining == 2, "The saved rest should resume crediting the whole away time (8 - 6).")
        #expect(state.canPostpone == false, "A resumed postponed break keeps postpone spent for the cycle.")
    }
}
