import AppKit

/// The system calls behind the two consents, so their bookkeeping can be tested.
struct ScreenCapturePermissionClient {
    var preflightAccess: @MainActor () -> Bool
    var requestAccess: @MainActor () -> Bool
    var confirmDirectCaptureAccess: @MainActor () async -> Bool
    var openSystemSettings: @MainActor () -> Void

    @MainActor
    static let live = Self(
        preflightAccess: { CGPreflightScreenCaptureAccess() },
        requestAccess: { CGRequestScreenCaptureAccess() },
        confirmDirectCaptureAccess: { await ScreenCapture.confirmDirectCaptureAccess() },
        openSystemSettings: {
            let settings = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            guard let url = URL(string: settings) else { return }
            NSWorkspace.shared.open(url)
        }
    )
}
