import Foundation
import Testing

@testable import ShatterBreak

/// What the reducer tests cannot reach: preferences read into it, its effects performed
/// against a screen that may be dark, and the system's sleep and wake reaching it.
@Suite("TimerState", .tags(.timerState))
@MainActor
struct TimerStateTests {
    let environment = TestEnvironment()
    let screen = PresenterSpy()

    private func makeState(work: Double = 10, rest: Double = 5) -> TimerState {
        let state = environment.makeTimerState(overlays: screen)
        state.workDurationSecs = work
        state.restDurationSecs = rest
        return state
    }

    @Test("a cycle puts the break on screen as work ends and takes it down as work resumes")
    func fullCycle() async {
        let state = makeState()
        state.start()
        #expect(screen.shown.isEmpty)

        await environment.advanceTime(by: 10)
        #expect(state.isResting)
        #expect(screen.shown == [.animated])
        #expect(screen.presentedState === state)

        await environment.advanceTime(by: 5)
        #expect(state.mode == .running)
        #expect(screen.presentedState == nil)
    }

    @Test("every session settles capture consent before its break needs it")
    func everySessionPrepares() async {
        let state = makeState()
        state.start()
        await environment.advanceTime(by: 10)
        await environment.advanceTime(by: 5)
        for _ in 0..<10 where screen.prepareCount < 2 { await Task.yield() }
        #expect(screen.prepareCount == 2)
    }

    @Test("a break falling due on a dark screen waits for one, while the plan moves on")
    func darkScreenHoldsTheBreak() async {
        let state = makeState()
        state.start()
        screen.hasAwakeScreen = false

        await environment.advanceTime(by: 10)
        #expect(state.isResting)
        #expect(screen.shown.isEmpty)

        screen.hasAwakeScreen = true
        state.reconcile()
        #expect(screen.shown == [.animated])
    }

    @Test("a break that ended behind a dark screen is announced settled")
    func heldBreakThatEndedIsSettled() async {
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)
        let state = makeState()
        state.start()
        screen.hasAwakeScreen = false

        await environment.advanceTime(by: 10)
        await environment.advanceTime(by: 5)
        #expect(state.awaitingReturn)

        screen.hasAwakeScreen = true
        state.reconcile()
        #expect(screen.shown == [.settled])
    }

    @Test("a break dismissed while the screen was dark never surfaces")
    func dismissedHeldBreakNeverSurfaces() async {
        let state = makeState()
        state.start()
        screen.hasAwakeScreen = false
        await environment.advanceTime(by: 10)

        state.stop()
        screen.hasAwakeScreen = true
        state.reconcile()
        #expect(screen.shown.isEmpty)
    }

    /// Issue #112.
    @Test("a stop landing on an unreconciled boundary never puts the break on screen")
    func stopOnUnreconciledBoundary() {
        let state = makeState()
        state.start()
        environment.clock.elapse(by: 11)

        state.stop()
        #expect(state.mode == .idle)
        #expect(screen.shown.isEmpty)
    }

    @Test("a long sleep reported by the system starts a fresh session on wake")
    func sleepAndWakeNotifications() {
        let state = makeState(work: 60, rest: 5)
        state.start()
        environment.clock.elapse(by: 20)

        state.systemWillSleep()
        environment.clock.sleepMachine(by: 600)
        state.systemDidWake()

        #expect(state.mode == .running)
        #expect(state.timeRemaining == 60)
    }

    @Test("pausing freezes the countdown and resuming continues from it")
    func pauseAndResume() async {
        let state = makeState()
        state.start()
        await environment.advanceTime(by: 3)
        state.pause()
        await environment.advanceTime(by: 100)
        #expect(state.timeRemaining == 7)

        state.resume()
        await environment.advanceTime(by: 2)
        #expect(state.timeRemaining == 5)
    }

    /// Issue #109: work auto-resuming after a break leaves the mode unchanged.
    @Test("every phase entry is a new countdown, even in the same mode")
    func intervalIdentity() async {
        let state = makeState()
        state.start()
        let first = state.countdownIntervalID
        await environment.advanceTime(by: 10)
        await environment.advanceTime(by: 5)
        #expect(state.mode == .running)
        #expect(state.countdownIntervalID != first)
    }

    @Test("postpone is offered in the break's opening window and hidden once used")
    func postponeButton() async {
        environment.defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        environment.defaults.set(2.0, forKey: PreferenceKeys.postponeWindowSecs)
        let state = makeState()
        state.start()
        await environment.advanceTime(by: 10)
        #expect(state.showsPostponeButton(at: environment.clock.date))
        #expect(state.showsPostponeButton(at: environment.clock.date + 2) == false)

        state.postpone()
        await environment.advanceTime(by: 60)
        #expect(state.isResting)
        #expect(state.showsPostponeButton(at: environment.clock.date) == false)
    }

    @Test("early return appears in the break's closing lead, and always once it has ended")
    func returnButton() async {
        environment.defaults.set(true, forKey: PreferenceKeys.allowEarlyReturn)
        environment.defaults.set(2.0, forKey: PreferenceKeys.earlyReturnLeadSecs)
        environment.defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)
        let state = makeState()
        state.start()
        await environment.advanceTime(by: 10)
        #expect(state.showsReturnButton(at: environment.clock.date) == false)
        #expect(state.showsReturnButton(at: environment.clock.date + 3))

        environment.defaults.set(false, forKey: PreferenceKeys.allowEarlyReturn)
        await environment.advanceTime(by: 5)
        #expect(state.showsReturnButton(at: environment.clock.date))
    }

    @Test(
        "the session lead counts only while it and tracking are both on",
        arguments: [(true, true, 1), (false, true, 0), (true, false, 0)]
    )
    func sessionLeadGating(tracking: Bool, leadOn: Bool, expected: Int) async {
        environment.defaults.set(tracking, forKey: PreferenceKeys.trackStatistics)
        environment.defaults.set(leadOn, forKey: PreferenceKeys.countSessionEarly)
        environment.defaults.set(3.0, forKey: PreferenceKeys.sessionLeadSecs)
        let state = makeState()
        state.start()
        await environment.advanceTime(by: 7)
        #expect(state.statistics.current.workSessionsCompleted == expected)
        #expect(state.mode == .running)
    }

    @Test("auto-start on launch starts an idle timer only, and only when enabled")
    func autoStart() {
        let state = makeState()
        state.autoStartIfEnabled()
        #expect(state.mode == .idle)

        environment.defaults.set(true, forKey: PreferenceKeys.autoStartOnLaunch)
        state.autoStartIfEnabled()
        #expect(state.mode == .running)
        let interval = state.countdownIntervalID
        state.autoStartIfEnabled()
        #expect(state.countdownIntervalID == interval)
    }

    @Test("a parked timer shows its plan and ignores everything")
    func parkedIsInert() {
        let state = TimerState.parked(.starting(.rest, duration: 30), defaults: environment.defaults)
        state.stop()
        state.postpone()
        state.systemDidWake()
        #expect(state.isResting)
    }

    @Test("the timer is released while subscribed to the system's sleep notifications")
    func deallocates() {
        weak var weakState: TimerState?
        do {
            let state = makeState()
            state.start()
            weakState = state
        }
        #expect(weakState == nil)
    }
}
