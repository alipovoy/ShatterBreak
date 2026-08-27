import Foundation
import Testing

@testable import ShatterBreak

/// The effect sample offered from Preferences (`Try It`).
///
/// Its justification is being a real break rather than a picture of one, so what these pin
/// down is the "real" part: the ordinary overlay path, the user's own break length, and
/// nothing left behind.
@Suite("Break effect trial", .tags(.overlays), .timeLimit(.minutes(1)))
@MainActor
struct BreakEffectTrialTests {
    /// The app's timer, which is also the trial's — one presenter, one break window.
    private func makeTimer(
        _ overlays: OverlayRecorder,
        defaults: any KeyValueStore = InMemoryKeyValueStore(),
        showing plan: TimerPlan? = nil
    ) -> TimerState {
        TimerState(
            overlays: overlays.presenter,
            defaults: defaults,
            clock: ManualTimerClock(),
            showing: plan
        )
    }

    private func makeTrial(
        _ overlays: OverlayRecorder,
        defaults: any KeyValueStore = InMemoryKeyValueStore(),
        duration: Duration = .milliseconds(20)
    ) -> BreakEffectTrial {
        BreakEffectTrial(timer: makeTimer(overlays, defaults: defaults), duration: duration)
    }

    @Test("a sample is presented like a break beginning now")
    func samplePresentsAnimated() {
        let overlays = OverlayRecorder()
        let trial = makeTrial(overlays)

        trial.start()

        #expect(overlays.showCount == 1)
        #expect(overlays.lastSettled == false, "The entrance is most of what there is to judge.")
        #expect(overlays.prepareCount == 1, "Shatter needs its consent settled before it can capture.")
        #expect(trial.isRunning)
    }

    @Test("the sample's clock reads like the user's own break")
    func sampleUsesTheConfiguredRestDuration() throws {
        let defaults = InMemoryKeyValueStore()
        defaults.set(420.0, forKey: PreferenceKeys.restDurationSecs)
        let overlays = OverlayRecorder()

        makeTrial(overlays, defaults: defaults).start()

        let sample = try #require(overlays.lastState)
        #expect(sample.isResting)
        #expect(sample.timeRemaining > 419, "A sample announcing someone else's break is a lie.")
    }

    @Test("starting again while a sample is up does not stack a second one")
    func startIsIdempotentWhileRunning() {
        let overlays = OverlayRecorder()
        let trial = makeTrial(overlays)

        trial.start()
        trial.start()

        #expect(overlays.showCount == 1)
    }

    @Test("ending dismisses the sample and allows another")
    func endDismissesAndReleases() {
        let overlays = OverlayRecorder()
        let trial = makeTrial(overlays)

        trial.start()
        trial.end()

        #expect(overlays.dismissCount == 1)
        #expect(trial.isRunning == false)

        trial.start()
        #expect(overlays.showCount == 2, "A finished sample must not block the next one.")
    }

    @Test("ending a sample that was never started dismisses nothing")
    func endWithoutStartIsInert() {
        let overlays = OverlayRecorder()

        makeTrial(overlays).end()

        #expect(overlays.dismissCount == 0, "Dismissing here would tear down a real break.")
    }

    @Test("a sample takes itself off the screen")
    func sampleEndsOnItsOwn() async throws {
        let overlays = OverlayRecorder()
        let trial = makeTrial(overlays, duration: .milliseconds(20))

        trial.start()
        try await Task.sleep(for: .milliseconds(200))

        #expect(overlays.dismissCount == 1, "Nobody should have to dismiss a sample they asked for.")
        #expect(trial.isRunning == false)
    }

    @Test("a sample does not outlive whatever put it up")
    func discardingTheTrialTakesTheSampleWithIt() {
        let overlays = OverlayRecorder()

        // Preferences closing mid-sample, which releases the trial it owns.
        do {
            let trial = makeTrial(overlays)
            trial.start()
        }

        #expect(overlays.dismissCount == 1, "A sample nobody owns is a break screen nobody can dismiss.")
    }

    @Test("a sample is refused while a real break owns the screen")
    func noSampleDuringARealBreak() {
        let overlays = OverlayRecorder()
        let resting = makeTimer(overlays, showing: .starting(.rest, duration: 300))
        let trial = BreakEffectTrial(timer: resting, duration: .milliseconds(20))

        #expect(trial.canStart == false)
        trial.start()

        #expect(overlays.showCount == 0, "There is one break window, and the break already has it.")
    }

    @Test("a break falling due mid-sample keeps the screen")
    func aRealBreakTakesTheWindowFromTheSample() {
        let overlays = OverlayRecorder()
        let timer = makeTimer(overlays)
        let trial = BreakEffectTrial(timer: timer, duration: .milliseconds(20))

        trial.start()
        // Presented through the same presenter, which makes it the window's owner.
        overlays.presenter.show(timer, .animated)
        trial.end()

        #expect(overlays.dismissCount == 0, "The sample's timeout must not close a real break.")
        #expect(overlays.presented === timer, "The break stays up.")
    }

    @Test("nothing a sample does is counted")
    func sampleNeverTouchesTheRealTally() throws {
        let defaults = InMemoryKeyValueStore()
        defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        defaults.set(true, forKey: PreferenceKeys.allowPostpone)
        let overlays = OverlayRecorder()

        makeTrial(overlays, defaults: defaults).start()
        let sample = try #require(overlays.lastState)
        sample.postpone()

        #expect(
            StatisticsStore(defaults: defaults).current.postponesUsed == 0,
            "A sample is a demonstration; the day's numbers are not its to write."
        )
    }
}
