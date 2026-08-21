import AppKit
import CoreGraphics
import Foundation

/// A seam over the two independent consents the shatter effect needs: classic Screen
/// Recording, which CoreGraphics can preflight and request, and macOS's separate
/// ``DirectCaptureAccess``, which can only be settled by attempting a capture.
///
/// Every operation is main-actor isolated, matching its sole caller and the AppKit and
/// CoreGraphics APIs behind it.
struct ScreenCapturePermissionClient {
    var preflightAccess: @MainActor () -> Bool
    var requestAccess: @MainActor () -> Bool

    /// Whether direct capture is currently allowed, learned by attempting one real
    /// request — there is no preflight for this one. The suspension inside hops the
    /// request off the main thread, so isolating the closure costs nothing.
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
