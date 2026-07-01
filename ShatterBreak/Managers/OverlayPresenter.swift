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
    var show: @MainActor (TimerState, OverlayPresentationStyle) -> Void
    var dismiss: @MainActor () -> Void
}

extension OverlayPresenter {
    /// A presenter backed by a freshly created `OverlayManager`, retained for the
    /// presenter's lifetime by the captured closures.
    @MainActor
    static func live(defaults: any KeyValueStore = UserDefaults.standard) -> OverlayPresenter {
        let manager = OverlayManager(defaults: defaults)
        return OverlayPresenter(
            show: { manager.showOverlays(state: $0, settled: $1 == .settled) },
            dismiss: { manager.dismissOverlays() }
        )
    }

    /// A no-op presenter for contexts where overlays are irrelevant.
    static let disabled = OverlayPresenter(show: { _, _ in }, dismiss: {})
}
