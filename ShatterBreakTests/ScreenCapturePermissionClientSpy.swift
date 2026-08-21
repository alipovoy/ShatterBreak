@testable import ShatterBreak

/// Records every call the permission manager makes and lets a test dictate the
/// answers, standing in for the two consents behind ``ScreenCapturePermissionClient``.
///
/// Main-actor isolated to match the client's closures, which are isolated (and so
/// implicitly `Sendable`) and therefore may only capture `Sendable` state.
@MainActor
final class ScreenCapturePermissionClientSpy {
    var preflightAccess = false
    var directCaptureAllowed = true
    private(set) var preflightCallCount = 0
    private(set) var requestCallCount = 0
    private(set) var openSettingsCallCount = 0
    private(set) var confirmDirectCaptureCallCount = 0

    var client: ScreenCapturePermissionClient {
        ScreenCapturePermissionClient(
            preflightAccess: { [unowned self] in
                preflightCallCount += 1
                return preflightAccess
            },
            requestAccess: { [unowned self] in
                requestCallCount += 1
                return preflightAccess
            },
            confirmDirectCaptureAccess: { [unowned self] in
                confirmDirectCaptureCallCount += 1
                return directCaptureAllowed
            },
            openSystemSettings: { [unowned self] in
                openSettingsCallCount += 1
            }
        )
    }
}
