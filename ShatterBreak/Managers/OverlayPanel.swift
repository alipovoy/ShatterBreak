import AppKit

/// The break overlay's window. Non-activating, so clicking its buttons leaves keyboard focus
/// with the user's app (issue #79); allowed key status, which borderless windows refuse, so
/// those clicks land.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}
