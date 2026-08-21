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
    /// session begins.
    ///
    /// Presentation has to be instantaneous, so anything that might put a system dialog
    /// on screen must happen well before the break — see ``DirectCaptureAccess`` and
    /// issue #90.
    var prepare: @MainActor () -> Void
    var show: @MainActor (TimerState, OverlayPresentationStyle) -> Void
    var dismiss: @MainActor () -> Void
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
                // Only the shatter effect captures the screen, so only it can raise the
                // system's capture dialogs. A user on Fogged or Dimmed is never asked.
                guard manager.selectedEffectType == .shatter else { return }
                Task { await permissions.prepareForCapture() }
            },
            show: { manager.showOverlays(state: $0, settled: $1 == .settled) },
            dismiss: { manager.dismissOverlays() }
        )
    }

    /// A no-op presenter for contexts where overlays are irrelevant.
    static let disabled = OverlayPresenter(prepare: {}, show: { _, _ in }, dismiss: {})
}
