import Foundation

/// The seam through which `TimerState` drives break overlays.
///
/// `TimerState` is a pure state machine and should not own AppKit windows, so it
/// reaches the overlay layer through these two closures. Production wires them to a
/// live `OverlayManager`; tests use ``disabled`` (or a small recorder) so the state
/// machine can be exercised without presenting real windows. This mirrors the
/// closure-based dependency seams used elsewhere (`ScreenCaptureClient`,
/// `ScreenCapturePermissionClient`).
///
/// See #41: this seam could be removed entirely by driving overlays from an observer
/// of `TimerState.mode` (visible iff `.resting`/`.awaitingReturn`) in the app layer.
struct OverlayPresenter {
    /// Settles the permissions the next break's overlay will need, called when a work
    /// session begins. Presentation has to be instantaneous, so anything that might put a
    /// system dialog on screen must happen well before the break (issue #90).
    var prepare: @MainActor () -> Void
    var show: @MainActor (TimerState, OverlayPresentationStyle) -> Void
    var dismiss: @MainActor () -> Void
    /// The timer whose break is currently on screen, or `nil` for nothing.
    ///
    /// The break window has one owner, so anything sharing this presenter has to be able
    /// to ask whether the window is still its own — dismissing on the strength of having
    /// shown something once would close whatever replaced it. Defaults to "nothing",
    /// which is the truthful answer for a presenter that never shows anything.
    var presenting: @MainActor () -> TimerState? = { nil }
}

extension OverlayPresenter {
    /// A presenter backed by a freshly created `OverlayManager`, retained for the
    /// presenter's lifetime by the captured closures.
    @MainActor
    static func live(defaults: any KeyValueStore = UserDefaults.standard) -> OverlayPresenter {
        let permissions = ScreenCapturePermissionManager.shared
        let manager = OverlayManager(
            defaults: defaults,
            directCaptureAccess: { permissions.directCaptureAccess }
        )
        return OverlayPresenter(
            prepare: {
                // Only an effect that captures the screen may raise the system's
                // capture dialogs; a user on Fogged or Dimmed is never asked.
                guard manager.selectedEffectType.requiresScreenCapture else { return }
                Task { await permissions.prepareForCapture() }
            },
            show: { manager.showOverlays(state: $0, settled: $1 == .settled) },
            dismiss: { manager.dismissOverlays() },
            presenting: { manager.presentedState }
        )
    }

    /// A no-op presenter for contexts where overlays are irrelevant.
    static let disabled = OverlayPresenter(prepare: {}, show: { _, _ in }, dismiss: {})
}
