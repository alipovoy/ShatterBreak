import AppKit
import CoreGraphics
import Foundation

struct ScreenCapturePermissionClient {
    var preflightAccess: () -> Bool
    var requestAccess: () -> Bool
    var openSystemSettings: () -> Void

    @MainActor
    static let live = Self(
        preflightAccess: {
            CGPreflightScreenCaptureAccess()
        },
        requestAccess: {
            CGRequestScreenCaptureAccess()
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
