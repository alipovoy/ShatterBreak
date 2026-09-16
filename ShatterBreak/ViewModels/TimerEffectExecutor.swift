import Foundation

/// Performs the effects ``TimerReducer`` emits, and decides when it is safe to.
///
/// The split exists because **macOS wakes with the display still dark**, and presenting a
/// break there burns it against a blank screen. The plan advances during a DarkWake while
/// anything facing the screen waits here, keeping display state out of the state machine.
@MainActor
final class TimerEffectExecutor {
    /// The world, as closures, mirroring the seams used for screen capture and overlays.
    struct Handlers {
        var prepareCapture: @MainActor () -> Void
        var showOverlay: @MainActor (OverlayPresentationStyle) -> Void
        var dismissOverlay: @MainActor () -> Void
        var record: @MainActor (StatisticsEvent) -> Void
        var resetStatisticsForNewSession: @MainActor () -> Void
    }

    private let handlers: Handlers
    /// Asked, not remembered: `screensDidWakeNotification` is a prompt to re-check, never the
    /// truth, and a break held behind a notification that never arrives is lost.
    ///
    /// Whether *any* attached display is awake, not only the main one — a break is only
    /// spent on nobody when every screen is dark.
    private let isDisplayAwake: @MainActor () -> Bool

    /// The break this batch will present, once ``flushIfPossible()`` finds it a screen. Not
    /// a queue: a second break replaces the first, since showing both would present a break
    /// the user already slept through — and a dismissal empties it outright.
    private(set) var deferredPresentation: OverlayPresentationStyle?

    init(
        handlers: Handlers,
        isDisplayAwake: @escaping @MainActor () -> Bool
    ) {
        self.handlers = handlers
        self.isDisplayAwake = isDisplayAwake
    }

    /// Performs `effects`, then resolves whatever presentation the batch left standing.
    ///
    /// The flush comes *last* so the batch is read whole: a break the same batch goes on to
    /// dismiss never reaches the screen, and a held one is not resolved against a plan those
    /// effects are about to invalidate (issue #112). An empty array is fine — every reconcile
    /// is also a flush, which is what backstops a wake notification that never comes.
    func perform(_ effects: [TimerEffect]) {
        for effect in effects {
            perform(effect)
        }
        flushIfPossible()
    }

    /// Presents the batch's surviving break, if there is a screen to present it on.
    func flushIfPossible() {
        guard let deferred = deferredPresentation, isDisplayAwake() else { return }

        deferredPresentation = nil
        handlers.showOverlay(deferred)
    }

    private func perform(_ effect: TimerEffect) {
        switch effect {
        case .prepareCapturePermissions:
            // Not gated: it puts nothing on screen, and holding it back is how consent ends
            // up being asked for mid-break.
            handlers.prepareCapture()

        case .showOverlay(let style):
            // Never presented from here, however lit the display: a break the rest of the
            // batch dismisses or settles must not reach the screen first (issue #112). The
            // slot also supersedes anything waiting, which is by definition out of date.
            deferredPresentation = style

        case .dismissOverlay:
            // A dismissed break must not appear when the display comes back.
            deferredPresentation = nil
            handlers.dismissOverlay()

        case .settleHeldOverlay:
            // Nothing is on screen to correct; this only demotes what is still waiting.
            guard deferredPresentation != nil else { return }
            deferredPresentation = .settled

        case .record(let event):
            handlers.record(event)

        case .resetStatisticsForNewSession:
            handlers.resetStatisticsForNewSession()
        }
    }
}
