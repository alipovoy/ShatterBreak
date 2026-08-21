import AppKit
import CoreGraphics
import Foundation

/// A seam over the two independent consents the shatter effect needs: classic Screen
/// Recording, which CoreGraphics can preflight and request, and macOS's separate
/// ``DirectCaptureAccess`` confirmation, which can only be settled by attempting a
/// capture.
///
/// Every operation is main-actor isolated, matching its sole caller
/// (``ScreenCapturePermissionManager``) and the AppKit and CoreGraphics APIs behind it.
struct ScreenCapturePermissionClient {
    var preflightAccess: @MainActor () -> Bool
    var requestAccess: @MainActor () -> Bool

    /// Settles macOS's direct-capture consent by attempting one real ScreenCaptureKit
    /// request, reporting whether direct capture is currently allowed. There is no
    /// preflight for this one: see ``DirectCaptureAccess``.
    ///
    /// The suspension inside hops the request itself off the main thread, so isolating
    /// the closure costs nothing.
    var confirmDirectCaptureAccess: @MainActor () async -> Bool

    var openSystemSettings: @MainActor () -> Void

    @MainActor
    static let live = Self(
        preflightAccess: {
            CGPreflightScreenCaptureAccess()
        },
        requestAccess: {
            CGRequestScreenCaptureAccess()
        },
        confirmDirectCaptureAccess: {
            await ScreenCaptureClient.confirmDirectCaptureAccess()
        },
        openSystemSettings: {
            guard
                let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
            else {
                return
            }

            NSWorkspace.shared.open(url)
        }
    )
}
