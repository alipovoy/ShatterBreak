import Foundation

/// The state of macOS's *direct capture* consent — the confirmation that sits on top of
/// Screen Recording permission and gates capturing the screen without routing the user
/// through `SCContentSharingPicker` (issue #90).
///
/// macOS 15 and later raise a separate system dialog — *"ShatterBreak is requesting to
/// bypass the system private window picker and directly access your screen and audio"* —
/// the first time an app takes ScreenCaptureKit's direct path, and re-raise it roughly
/// once a month. It is invisible to `CGPreflightScreenCaptureAccess()`, which reports only
/// classic Screen Recording, so the sole way to learn the answer is to attempt a capture.
/// ``ScreenCapturePermissionManager`` therefore attempts one deliberately, when a work
/// session begins, instead of letting the break be the first to find out.
enum DirectCaptureAccess: Equatable, Sendable {
    /// Not yet attempted since launch. Treated as permitted: the app must not downgrade
    /// the shatter effect over a refusal it has never actually observed.
    case unknown

    /// A capture request went through, so the system is currently allowing direct capture.
    case allowed

    /// A capture request failed, so the break falls back to ``EffectType/fogged`` rather
    /// than re-raising the system dialog on top of the overlay.
    case refused
}
