import AppKit

/// The borderless, non-activating panel that hosts a break overlay.
///
/// Overlay buttons ("Postpone", "I'm back") must be clickable without activating
/// ShatterBreak: a click on a regular window activates its app, deactivating
/// whatever the user was working in, so dismissing the break left keyboard focus
/// stranded and keystrokes went nowhere (issue #79). The `.nonactivatingPanel`
/// style keeps the user's app active across the whole break, and focus lands back
/// in their document the moment the panel orders out.
///
/// Borderless windows refuse key status by default, so `canBecomeKey` is opened up
/// to let the panel receive its button clicks first-class while it is frontmost.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }
}
