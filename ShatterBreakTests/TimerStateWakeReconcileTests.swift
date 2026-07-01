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
        // Simulate a work session that follows a postpone (start() leaves the flag set), so
        // the from-work crossing's refreshingPostpone reset is observable via canPostpone.
        state.hasPostponeBeenUsedThisCycle = true

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away longer than the 5s of work left but less than a full 10s break: work is
        // consumed and the whole 7s away is credited as rest, leaving 10 - 7 = 3s.
        environment.elapseTimeWithoutTick(by: 7)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "Crossing into the break on wake should enter the rest phase.")
        #expect(state.timeRemaining == 3, "The break should resume with the whole away time credited as rest.")
        #expect(recorder.showCount == 1, "Crossing into the break should present the break overlay.")
        #expect(recorder.dismissCount == 0, "Crossing into the break should not dismiss an overlay.")
        #expect(state.canPostpone, "A brand-new cycle's break re-grants postpone (refreshingPostpone: true).")
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
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter, postponeDurationSecs: 5)
        state.workDurationSecs = 1
        state.restDurationSecs = 8

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")
        #expect(recorder.dismissCount == 1, "Postponing should dismiss the break overlay.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away 6s: longer than the 5s of postpone work, shorter than the 8s saved rest,
        // so the saved break resumes with 8 - 6 = 2s, crediting the whole absence.
        environment.elapseTimeWithoutTick(by: 6)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "Crossing into the saved break should re-enter rest.")
        #expect(state.timeRemaining == 2, "The saved rest should resume crediting the whole away time (8 - 6).")
        #expect(state.canPostpone == false, "A resumed postponed break keeps postpone spent for the cycle.")
        #expect(recorder.showCount == 2, "The overlay dismissed at postpone must be re-presented on the crossing.")
    }

    @Test("a short absence after partly-elapsed work resumes from the sleep-time remainder")
    @MainActor
    func shortAbsenceAfterPartialWorkResumesWork() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 10
        state.restDurationSecs = 5

        state.start()
        await environment.advanceTime(by: 4)
        #expect(state.timeRemaining == 6, "Four seconds of work should elapse before sleep (W = 6).")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away 4s <= the 6s of work left AT SLEEP, so work resumes with 6 - 4 = 2s. Measuring
        // work-left at wake instead would see ~2s left and wrongly cross into a break.
        environment.elapseTimeWithoutTick(by: 4)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.mode == .running, "A short absence within the remaining work should resume work.")
        #expect(state.timeRemaining == 2, "Work resumes from the sleep-time remainder minus the away time.")
    }

    @Test("a crossing absence after partly-elapsed work uses the sleep-time work remainder")
    @MainActor
    func crossingAbsenceAfterPartialWorkUsesSleepRemainder() async {
        let environment = TestEnvironment()
        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter)
        state.workDurationSecs = 10
        state.restDurationSecs = 8

        state.start()
        await environment.advanceTime(by: 7)
        #expect(state.timeRemaining == 3, "Seven seconds of work should elapse before sleep (W = 3).")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away 5s > the 3s of work left AT SLEEP but < the 8s break, so it crosses into a
        // prorated break of 8 - 5 = 3s. Using the full 10s duration would keep resuming work.
        environment.elapseTimeWithoutTick(by: 5)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.isResting, "The absence crossed the sleep-time work remainder into the break.")
        #expect(state.timeRemaining == 3, "The break resumes crediting the whole away time (8 - 5).")
        #expect(recorder.showCount == 1, "Crossing into the break should present the break overlay.")
    }

    @Test("long absence during postponed work awaits the user in manual mode")
    @MainActor
    func longAbsenceDuringPostponedWorkAwaitsUserInManualMode() async {
        let environment = TestEnvironment()
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let recorder = OverlayRecorder()
        let state = environment.makeTimerState(overlays: recorder.presenter, postponeDurationSecs: 5)
        state.workDurationSecs = 1
        state.restDurationSecs = 3

        state.start()
        await environment.advanceUntil(maxTicks: 2) { state.isResting }
        state.postpone()
        #expect(state.mode == .postponedWork, "Postpone should switch into postponed work.")

        let notificationCenter = environment.workspaceNotificationCenter
        notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Away at least a full break: the absence is the break itself. Manual mode must wait
        // for the user and must discard the in-flight saved break (issues #69, #72).
        environment.elapseTimeWithoutTick(by: 4)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(state.awaitingReturn, "Manual mode should await the user after a long postponed-work absence.")
        #expect(state.isRunning == false, "Work must not silently restart in manual mode.")
        #expect(state.savedRestRemaining == nil, "The in-flight saved break must be discarded, not leaked.")
        #expect(recorder.showCount == 2, "The break-end window is presented after the earlier postpone overlay.")

        state.start()
        #expect(state.isRunning, "Starting from the break-end window should begin a fresh work session.")
        #expect(state.timeRemaining == 1, "The fresh session should restore the full work duration.")
    }
}
