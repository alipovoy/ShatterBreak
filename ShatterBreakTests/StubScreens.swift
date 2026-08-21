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

    /// A client that reports these displays and captures `image` for each display asked
    /// for, so a test can drive the real shatter path. Pair it with a manager whose
    /// direct-capture access is `.allowed`, or the effect resolves to fogged instead.
    func capturingClient(image: CGImage) -> ScreenCaptureClient {
        ScreenCaptureClient(
            hasPermission: { true },
            availableScreens: { [unowned self] in screens },
            captureImages: { displayIDs in
                Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, image) })
            }
        )
    }

    /// A display of `size` at horizontal offset `x`. Tests really present windows, so
    /// sizes stay small; the default is a single pixel, barely touching the screen.
    static func display(
        _ displayID: CGDirectDisplayID,
        x: CGFloat = 0,
        size: CGSize = CGSize(width: 1, height: 1)
    ) -> ScreenInfo {
        ScreenInfo(displayID: displayID, frame: CGRect(origin: CGPoint(x: x, y: 0), size: size))
    }
}
