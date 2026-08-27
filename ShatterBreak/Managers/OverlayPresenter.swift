import Foundation

/// The seam through which `TimerState` drives break overlays.
///
/// `TimerState` is a pure state machine and should not own AppKit windows, so it reaches the
/// overlay layer through closures — the same seam used for `ScreenCaptureClient`. Production
/// wires them to a live `OverlayManager`; tests use ``disabled`` or a recorder.
struct OverlayPresenter {
    /// Settles the permissions the next break will need, at the head of a work session:
    /// presentation is instantaneous, so a possible system dialog must come well before the
    /// break.
    var prepare: @MainActor () -> Void
    var show: @MainActor (TimerState, OverlayPresentationStyle) -> Void
    var dismiss: @MainActor () -> Void
    /// The timer whose break is on screen, so that anything sharing this presenter can ask
    /// whether the window is still its own before taking it down.
    var presenting: @MainActor () -> TimerState? = { nil }
}

extension OverlayPresenter {
    /// Backed by a fresh `OverlayManager`, retained by the captured closures.
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
