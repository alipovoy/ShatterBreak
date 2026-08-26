import Testing

@testable import ShatterBreak

/// Records what the executor asked the world to do.
@MainActor
private final class EffectRecorder {
    private(set) var prepareCount = 0
    private(set) var shown: [OverlayPresentationStyle] = []
    private(set) var dismissCount = 0
    private(set) var recorded: [StatisticsEvent] = []
    private(set) var resetCount = 0

    var handlers: TimerEffectExecutor.Handlers {
        TimerEffectExecutor.Handlers(
            prepareCapture: { [unowned self] in prepareCount += 1 },
            showOverlay: { [unowned self] in shown.append($0) },
            dismissOverlay: { [unowned self] in dismissCount += 1 },
            record: { [unowned self] in recorded.append($0) },
            resetStatisticsForNewSession: { [unowned self] in resetCount += 1 }
        )
    }
}

/// A display the test switches on and off.
@MainActor
private final class StubDisplay {
    var isAwake = true
}

@Suite("Timer effect executor", .tags(.timerState, .overlays))
struct TimerEffectExecutorTests {
    @MainActor
    private func makeExecutor(_ recorder: EffectRecorder, display: StubDisplay) -> TimerEffectExecutor {
        TimerEffectExecutor(handlers: recorder.handlers, isDisplayAwake: { display.isAwake })
    }

    @Test("effects reach the world in the order the reducer emitted them")
    @MainActor
    func effectsAreForwardedInOrder() {
        let recorder = EffectRecorder()
        let executor = makeExecutor(recorder, display: StubDisplay())

        executor.perform([.record(.workSessionCompleted), .showOverlay(.animated), .prepareCapturePermissions])

        #expect(recorder.recorded == [.workSessionCompleted], "The completed session should be tallied.")
        #expect(recorder.shown == [.animated], "The break overlay should be presented.")
        #expect(recorder.prepareCount == 1, "Capture consent should be settled.")
    }

    @Test("a break coming due on a dark screen waits for a display")
    @MainActor
    func presentationWaitsForADisplay() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.record(.workSessionCompleted), .showOverlay(.animated)])

        // macOS wakes to service background work with the display still off. Shattering
        // onto a screen nobody is looking at spends the break for nothing (#99, #107).
        #expect(recorder.shown.isEmpty, "A break must not be presented onto a dark screen.")
        #expect(
            recorder.recorded == [.workSessionCompleted],
            "The plan still advanced and its bookkeeping still happened; only the screen waits."
        )

        display.isAwake = true
        // Any reconcile is a retry, so the heartbeat gets there even if no wake
        // notification ever arrives.
        executor.perform([])
        #expect(recorder.shown == [.animated], "The held break should be presented once there is a screen.")
    }

    @Test("a break dismissed while the screen was dark never appears")
    @MainActor
    func dismissedPresentationIsDropped() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.showOverlay(.animated)])
        // What a reconcile on wake does when the break elapsed while the display was off.
        executor.perform([.dismissOverlay])
        display.isAwake = true
        executor.flushIfPossible()

        #expect(recorder.shown.isEmpty, "A dismissed break must not surface when the display returns.")
        #expect(recorder.dismissCount == 1, "The dismissal itself still goes through.")
    }

    @Test("only the latest held presentation survives")
    @MainActor
    func onlyTheLatestPresentationIsHeld() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.showOverlay(.animated)])
        // A later reconcile decided the break had already elapsed and owes a settled window.
        executor.perform([.showOverlay(.settled)])
        display.isAwake = true
        executor.flushIfPossible()

        #expect(
            recorder.shown == [.settled],
            "Holding a queue would present a break the user already slept through, then another."
        )
    }

    @Test("waking with nothing held presents nothing")
    @MainActor
    func wakingWithNothingHeldIsQuiet() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        display.isAwake = true
        executor.flushIfPossible()

        #expect(recorder.shown.isEmpty, "A wake is not by itself a reason to present anything (issue #94).")
        #expect(recorder.dismissCount == 0, "Nor a reason to dismiss anything.")
    }
}
