import CoreGraphics

@testable import ShatterBreak

/// A display list a test can change between reconciliation passes.
@MainActor
final class StubScreens {
    var screens: [ScreenInfo]

    init(_ screens: [ScreenInfo]) {
        self.screens = screens
    }

    /// A display of `size` at horizontal offset `x`. Tests really present windows, so sizes
    /// stay small.
    static func display(
        _ displayID: CGDirectDisplayID,
        x: CGFloat = 0,
        size: CGSize = CGSize(width: 1, height: 1)
    ) -> ScreenInfo {
        ScreenInfo(displayID: displayID, frame: CGRect(origin: CGPoint(x: x, y: 0), size: size))
    }
}
