import Foundation
import Testing

@testable import ShatterBreak

/// The effect sample offered from Preferences (`Try It`).
///
/// Its whole justification is that it is a real break rather than a picture of one, so
/// what these pin down is the "real" part: it presents through the ordinary overlay
/// path, with the user's own break length, and leaves nothing behind when it ends.
@Suite("Break effect trial", .tags(.overlays), .timeLimit(.minutes(1)))
@MainActor
struct BreakEffectTrialTests {
    private func makeTrial(
        _ overlays: OverlayRecorder,
        defaults: any KeyValueStore = InMemoryKeyValueStore(),
        duration: Duration = .milliseconds(20)
    ) -> BreakEffectTrial {
        BreakEffectTrial(overlays: overlays.presenter, defaults: defaults, duration: duration)
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
