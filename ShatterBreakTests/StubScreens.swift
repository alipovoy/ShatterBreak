import CoreGraphics

@testable import ShatterBreak

/// A mutable display list backing a stub ``ScreenCaptureClient``, so a test can
/// reconfigure the attached displays between reconciliation passes.
@MainActor
final class StubScreens {
    var screens: [ScreenInfo]

    init(_ screens: [ScreenInfo]) {
        self.screens = screens
    }

    /// A client that reports these displays and never captures. `hasPermission` is
    /// `false`, so shatter resolves to fogged and no capture task is started —
    /// keeping presentation tests synchronous.
    var captureClient: ScreenCaptureClient {
        ScreenCaptureClient(
            hasPermission: { false },
            availableScreens: { [unowned self] in screens },
            captureImages: { _ in [:] }
        )
    }

    /// A one-pixel display, so tests that really present a window barely touch the screen.
    static func display(_ displayID: CGDirectDisplayID, x: CGFloat = 0) -> ScreenInfo {
        ScreenInfo(displayID: displayID, frame: CGRect(x: x, y: 0, width: 1, height: 1))
    }
}
