import Foundation

/// macOS 15+'s second screen-capture consent: the *"requesting to bypass the system
/// private window picker"* dialog, raised when an app captures without
/// `SCContentSharingPicker` and re-raised roughly monthly (issue #90).
///
/// `CGPreflightScreenCaptureAccess()` reports only classic Screen Recording and cannot
/// see this one, so the only way to learn the answer is to attempt a capture — which is
/// why ``ScreenCapturePermissionManager`` attempts one when a work session begins rather
/// than letting the break be the first to find out.
enum DirectCaptureAccess: Equatable, Sendable {
    /// Not yet attempted. Treated as permitted: the app must not downgrade the shatter
    /// effect over a refusal it has never observed.
    case unknown

    case allowed

    /// The break falls back to ``EffectType/fogged`` rather than re-raising the system
    /// dialog on top of the overlay.
    case refused
}
