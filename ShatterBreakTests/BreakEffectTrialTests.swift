import Foundation
import Testing

@testable import ShatterBreak

/// The sample borrows the one break window, so everything here is about who owns it.
@Suite("Break effect trial", .tags(.overlays))
@MainActor
struct BreakEffectTrialTests {
    let environment = TestEnvironment()
    let screen = PresenterSpy()

    @Test("a sample is shown like a break beginning now, and ending takes it down")
    func sampleLifecycle() async {
        let timer = environment.makeTimerState(overlays: screen)
        let trial = BreakEffectTrial(timer: timer, duration: .seconds(60))

        await trial.start()
        #expect(screen.shown == [.animated])
        #expect(screen.presentedState?.isResting == true)
        #expect(screen.prepareCount == 1)

        trial.end()
        #expect(screen.presentedState == nil)
        #expect(trial.canStart)
    }

    @Test("a sample is refused while a real break owns the screen")
    func refusedDuringBreak() async {
        let timer = environment.makeTimerState(overlays: screen)
        timer.workDurationSecs = 10
        timer.start()
        await environment.advanceTime(by: 10)

        let trial = BreakEffectTrial(timer: timer)
        await trial.start()
        #expect(screen.shown == [.animated])
        #expect(screen.presentedState === timer)
    }

    @Test("a break that takes the window mid-sample keeps it, and keeps its clicks")
    func realBreakWinsTheWindow() async {
        let timer = environment.makeTimerState(overlays: screen)
        timer.workDurationSecs = 10
        timer.start()
        let trial = BreakEffectTrial(timer: timer, duration: .seconds(60))
        await trial.start()

        await environment.advanceTime(by: 10)
        #expect(screen.presentedState === timer)

        #expect(trial.interrupt() == false, "The click is the real break's.")
        #expect(screen.presentedState === timer)
    }
}
