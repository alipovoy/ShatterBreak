import CoreGraphics
import Foundation

/// Performs the effects ``TimerReducer`` emits, and decides when it is safe to.
///
/// The split matters for exactly one reason: **macOS wakes with the display still dark.**
/// A DarkWake services background work with nobody looking at the screen, and presenting a
/// break there burns it against a blank display. That is why automatic recovery was
/// rejected in the #99 and #107 design reviews, and the rewrite must not reintroduce it by
/// the back door.
///
/// So the plan advances during a DarkWake — time really did pass, and pretending otherwise
/// is what stalls a timer — while anything that faces the screen waits here until there is
/// a screen to face. The state machine stays free of display state, which is what let the
/// old design's screen concerns leak into transition logic in the first place.
@MainActor
final class TimerEffectExecutor {
    /// The world, as closures. Keeps this type independent of `TimerState` and of AppKit,
    /// and mirrors the seams already used for screen capture and overlays.
    struct Handlers {
        var prepareCapture: @MainActor () -> Void
        var showOverlay: @MainActor (OverlayPresentationStyle) -> Void
        var dismissOverlay: @MainActor () -> Void
        var record: @MainActor (StatisticsEvent) -> Void
        var resetStatisticsForNewSession: @MainActor () -> Void
    }

    private let handlers: Handlers
    /// Whether there is a lit screen to present on.
    ///
    /// Asked, not remembered. `screensDidWakeNotification` is a prompt to re-check, never
    /// the source of truth: a break held behind a notification that never arrives is the
    /// same class of bug as a transition held behind a wake that never arrives (#87).
    private let isDisplayAwake: @MainActor () -> Bool

    /// The one presentation waiting for a screen, if any.
    ///
    /// One, not a queue: a second break coming due before the first was ever shown replaces
    /// it. Showing both would present a break the user already slept through.
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
    /// The retry comes *last* so the batch has had its say first. Flushing up front would
    /// resolve a held presentation against a plan the same batch is about to invalidate —
    /// a break window shattering onto the screen with its chime a moment before the
    /// dismissal in the very same batch tears it down.
    ///
    /// Callers pass an empty array freely: every reconcile is also a retry, which is what
    /// makes the heartbeat the backstop for a `screensDidWakeNotification` that never comes.
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
            // Not gated: this settles consent, it puts nothing on screen of its own, and
            // holding it back is how consent ends up being asked for mid-break (#90).
            handlers.prepareCapture()

        case .showOverlay(let style):
            // Supersedes anything waiting, presented or not: this is the current answer,
            // and the held one is by definition out of date.
            deferredPresentation = nil
            guard isDisplayAwake() else {
                deferredPresentation = style
                return
            }
            handlers.showOverlay(style)

        case .dismissOverlay:
            // Also cancels anything waiting: a break that has been dismissed must not
            // appear when the display comes back.
            deferredPresentation = nil
            handlers.dismissOverlay()

        case .settleHeldOverlay:
            // The break a held presentation would have announced is over. Nothing is on
            // screen to correct, so this only demotes what is still waiting.
            guard deferredPresentation != nil else { return }
            deferredPresentation = .settled

        case .record(let event):
            handlers.record(event)

        case .resetStatisticsForNewSession:
            handlers.resetStatisticsForNewSession()
        }
    }
}
