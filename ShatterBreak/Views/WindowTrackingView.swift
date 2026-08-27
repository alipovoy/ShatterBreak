import AppKit

/// A zero-size `NSView` that reports the window it lands in.
///
/// SwiftUI cannot ask "which `NSWindow` am I in?", but an `NSView` is told when it is moved
/// into one — which is how ``ActiveSpaceWindowModifier`` and
/// ``MenuWindowVisibilityObserver`` reach a window AppKit still owns.
///
/// `onWindowChange` fires with `nil` on leaving a window, making it an observer rather than
/// a one-shot lookup.
final class WindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
