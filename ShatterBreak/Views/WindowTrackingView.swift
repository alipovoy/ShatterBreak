import AppKit

/// A zero-size view reporting the window it lands in, and `nil` when it leaves: SwiftUI
/// cannot ask which `NSWindow` it is in.
final class WindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
