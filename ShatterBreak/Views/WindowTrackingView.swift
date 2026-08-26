import AppKit

/// A zero-size `NSView` whose only job is to report the window it lands in.
///
/// SwiftUI has no way to ask "which `NSWindow` am I in?", but an `NSView` is told when it
/// is moved into one. Placed in a SwiftUI hierarchy through an `NSViewRepresentable`, this
/// is how a view reaches its own window to set something AppKit still owns:
/// ``ActiveSpaceWindowModifier`` sets the window's collection behaviour, and
/// ``MenuWindowVisibilityObserver`` watches it appear and disappear.
///
/// `onWindowChange` fires with `nil` when the view leaves a window, which is what makes it
/// an observer rather than a one-shot lookup.
final class WindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
