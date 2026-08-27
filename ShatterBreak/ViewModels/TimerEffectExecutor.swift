import CoreGraphics
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
    private let isDisplayAwake: @MainActor () -> Bool

    /// The one presentation waiting for a screen. Not a queue: a second break replaces the
    /// first, since showing both would present a break the user already slept through.
    private(set) var deferredPresentation: OverlayPresentationStyle?

    init(
        handlers: Handlers,
        isDisplayAwake: @escaping @MainActor () -> Bool = { CGDisplayIsAsleep(CGMainDisplayID()) == 0 }
    ) {
        self.handlers = handlers
        self.isDisplayAwake = isDisplayAwake
    }

    /// Performs `effects`, then retries anything still waiting for a screen.
    ///
    /// The retry comes *last*: flushing first would resolve a held presentation against a
    /// plan the same batch is about to invalidate. An empty array is fine — every reconcile
    /// is also a retry, which is what backstops a wake notification that never comes.
    func perform(_ effects: [TimerEffect]) {
        for effect in effects {
            perform(effect)
        }
        flushIfPossible()
    }

    /// Presents anything held back, if there is now a screen to present it on.
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
            // Supersedes anything waiting: the held one is by definition out of date.
            deferredPresentation = nil
            guard isDisplayAwake() else {
                deferredPresentation = style
                return
            }
            handlers.showOverlay(style)

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
