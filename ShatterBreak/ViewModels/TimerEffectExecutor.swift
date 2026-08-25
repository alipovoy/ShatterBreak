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
    private(set) var screensAreAwake = true
    /// The one presentation waiting for a screen, if any.
    ///
    /// One, not a queue: a second break coming due before the first was ever shown replaces
    /// it. Showing both would present a break the user already slept through.
    private(set) var deferredPresentation: OverlayPresentationStyle?

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    func perform(_ effects: [TimerEffect]) {
        for effect in effects {
            perform(effect)
        }
    }

    /// The display went dark. Presentations from here on wait.
    func screensDidSleep() {
        screensAreAwake = false
    }

    /// There is a screen again. Anything held back is presented now.
    ///
    /// Callers reconcile *before* calling this, so a break that elapsed while the display
    /// was dark has already been resolved — and its pending presentation already replaced
    /// or dismissed — rather than surfacing after the fact.
    func screensDidWake() {
        screensAreAwake = true
        guard let deferred = deferredPresentation else { return }

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
            guard screensAreAwake else {
                deferredPresentation = style
                return
            }
            handlers.showOverlay(style)

        case .dismissOverlay:
            // Also cancels anything waiting: a break that has been dismissed must not
            // appear when the display comes back.
            deferredPresentation = nil
            handlers.dismissOverlay()

        case .record(let event):
            handlers.record(event)

        case .resetStatisticsForNewSession:
            handlers.resetStatisticsForNewSession()
        }
    }
}
