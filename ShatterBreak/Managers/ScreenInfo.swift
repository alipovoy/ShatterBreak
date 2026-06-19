import CoreGraphics

/// A minimal, value-type description of a connected display.
///
/// Abstracting `NSScreen` behind a `Sendable` value lets the overlay pipeline be
/// exercised in tests without a live window server, while still carrying the two
/// pieces ``OverlayManager`` needs: the display's identifier and its frame.
struct ScreenInfo: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
}
