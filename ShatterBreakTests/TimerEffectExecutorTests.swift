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

        // A DarkWake leaves the display off; shattering there spends the break.
        #expect(recorder.shown.isEmpty, "A break must not be presented onto a dark screen.")
        #expect(
            recorder.recorded == [.workSessionCompleted],
            "The plan still advanced and its bookkeeping still happened; only the screen waits."
        )

        display.isAwake = true
        // Any reconcile is a retry, so the heartbeat suffices without a wake notification.
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

    @Test("a dismissal in the same batch cancels a held break before it can flash")
    @MainActor
    func batchDismissalBeatsTheFlush() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.showOverlay(.animated)])

        // The display wakes in a break's closing seconds. Retrying the held presentation
        // before the batch would shatter it onto the screen a moment before the same batch
        // tore it down.
        display.isAwake = true
        executor.perform([.record(.breakCompleted), .prepareCapturePermissions, .dismissOverlay])

        #expect(recorder.shown.isEmpty, "A break the same batch dismisses must never reach the screen.")
        #expect(recorder.dismissCount == 1, "The dismissal itself still goes through.")
    }

    @Test("a presentation in the same batch supersedes a held one even on a lit display")
    @MainActor
    func batchPresentationSupersedesAHeldOne() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.showOverlay(.animated)])

        display.isAwake = true
        executor.perform([.showOverlay(.settled)])

        #expect(
            recorder.shown == [.settled],
            "The current answer replaces the held one; flushing it afterwards would stack a stale break on top."
        )
    }

    @Test("a held break whose break has ended loses its entrance")
    @MainActor
    func settlingDemotesAHeldPresentation() {
        let recorder = EffectRecorder()
        let display = StubDisplay()
        let executor = makeExecutor(recorder, display: display)

        display.isAwake = false
        executor.perform([.showOverlay(.animated)])
        // The break ran out while the display stayed dark.
        executor.perform([.record(.breakCompleted), .settleHeldOverlay])

        display.isAwake = true
        executor.perform([])

        #expect(
            recorder.shown == [.settled],
            "Announcing a break that ended while the screen was off, with a shake and a chime, is issues #76 and #94."
        )
    }

    @Test("settling does nothing when nothing is held")
    @MainActor
    func settlingWithNothingHeldIsQuiet() {
        let recorder = EffectRecorder()
        let executor = makeExecutor(recorder, display: StubDisplay())

        executor.perform([.settleHeldOverlay])

        #expect(recorder.shown.isEmpty, "There is no held break to correct, and none to conjure.")
        #expect(recorder.dismissCount == 0, "Nor anything to take down.")
    }
}
