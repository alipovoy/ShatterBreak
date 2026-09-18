import AppKit
import SwiftUI

/// The status item and the popover holding ``MenuView``.
///
/// AppKit rather than `MenuBarExtra`: that scene drops font modifiers on its label, so the
/// countdown drew proportionally and the item resized every tick. Monospaced digits hold
/// the width instead.
///
/// The popover hangs off an anchor window rather than the item: AppKit moves a popover
/// whose positioning view resizes, landing it ~48pt off.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let state: TimerState
    private let defaults: any KeyValueStore
    private let notificationCenter: NotificationCenter
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    /// Built from the menu bar's own point size, read before anything overrides
    /// `button.font`, which is what keeps the baseline where AppKit put it.
    private let titleAttributes: [NSAttributedString.Key: Any]

    /// Parked where the item was when the menu opened, and left there.
    private var anchorWindow: NSWindow?

    /// Both read in ``press(menuIsShown:)``.
    private var dismissalIsUnanswered = false
    private var isClosing = false

    private var refreshTask: Task<Void, Never>?
    private var styleObserver: (any NSObjectProtocol)?
    private var timerStyle: MenuBarTimerStyle

    init(
        state: TimerState,
        defaults: any KeyValueStore = UserDefaults.standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.state = state
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.timerStyle = defaults.value(
            forKey: PreferenceKeys.menuBarTimerStyle,
            default: PreferenceDefaults.menuBarTimerStyle
        )
        let pointSize = statusItem.button?.font?.pointSize ?? NSFont.systemFontSize
        self.titleAttributes = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        ]
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "app.badge.clock", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuView(state: state))

        styleObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.styleDidChange() }
        }

        observeState()
        restart()
    }

    isolated deinit {
        refreshTask?.cancel()
        if let styleObserver {
            notificationCenter.removeObserver(styleObserver)
        }
        anchorWindow?.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Popover

    enum PressOutcome {
        case swallowed, closes, opens
    }

    /// A click on the item deactivates the app, dismissing the menu 28ms before the action runs,
    /// on the deactivation rather than the click. The two cannot be matched up by event, only by
    /// order — a dismissal the item caused is followed by a press, one caused elsewhere is not.
    ///
    /// A press that dismissed nothing — VoiceOver, Full Keyboard Access — has to close the menu
    /// itself. A menu still fading reads as shown, and is reopened rather than closed again.
    func press(menuIsShown: Bool) -> PressOutcome {
        guard dismissalIsUnanswered == false else {
            dismissalIsUnanswered = false
            return .swallowed
        }
        return menuIsShown && isClosing == false ? .closes : .opens
    }

    @objc private func togglePopover() {
        switch press(menuIsShown: popover.isShown) {
        case .swallowed: return
        case .closes: closeMenu()
        case .opens: showMenu()
        }
    }

    /// `willClose` fires inside `performClose`; a close this class asked for is answered
    /// already, and left unanswered it would swallow the next press.
    private func closeMenu() {
        popover.performClose(nil)
        dismissalIsUnanswered = false
    }

    private func showMenu() {
        guard let anchor = stageAnchor() else { return }

        // Deprecated, but the `activate()` that replaced it declines to bring an accessory
        // app forward — measured leaving the menu with no key window at all.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)

        popover.contentViewController?.view.window?.makeKey()
        dropFirstResponder()
    }

    /// The duration field takes first responder as the window appears, being the first control
    /// that accepts one. At `didShow` alone the field holds it for the length of the fade;
    /// here alone misses a menu reopened while the last was closing.
    private func dropFirstResponder() {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    /// A menu shown over one still closing may never see that close's `didClose`.
    func popoverDidShow(_ notification: Notification) {
        isClosing = false
        dropFirstResponder()
    }

    func popoverWillClose(_ notification: Notification) {
        dismissalIsUnanswered = true
        isClosing = true
    }

    /// Unanswered by now means a click elsewhere.
    func popoverDidClose(_ notification: Notification) {
        dismissalIsUnanswered = false
        isClosing = false
    }

    /// From the trailing edge, the one coordinate a status item keeps when its width
    /// changes: from the centre, stopping a session from an open menu leaves the arrow
    /// beside the item. 16pt is where the icon sits with the countdown hidden.
    private static let anchorInset: CGFloat = 16

    func stageAnchor() -> NSView? {
        guard let screenRect = itemScreenFrame else { return nil }

        let window = anchorWindow ?? makeAnchorWindow()
        anchorWindow = window
        window.setFrameOrigin(NSPoint(x: screenRect.maxX - Self.anchorInset, y: screenRect.minY))
        window.orderFront(nil)
        return window.contentView
    }

    private func makeAnchorWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 1, height: 1)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        // Without this the anchor — and so the menu hanging off it — stays on the Space it
        // was first ordered onto, while the status item is on all of them.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }

    // MARK: - Refresh

    /// Captures no strong `self` across the await, which is what keeps `deinit` reachable
    /// while the loop sleeps — and so lets the status item go.
    ///
    /// Configures inside the task rather than at the call site: the two must read the same
    /// mode, and by the time the task body runs the state that triggered it may have moved on.
    private func restart() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self, state] in
            self?.configure()
            guard let style = self?.displayStyle else { return }
            await style.driveCountdown(for: state) { [weak self] referenceDate in
                self?.render(at: referenceDate)
            }
        }
    }

    /// `withObservationTracking` fires once, on willSet, so the handler re-registers before
    /// reacting — registering anywhere else leaves a second tracker armed for every one the
    /// handler adds.
    private func observeState() {
        withObservationTracking {
            _ = state.mode
            _ = state.countdownIntervalID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeState()
                self?.restart()
            }
        }
    }

    private func styleDidChange() {
        let stored: MenuBarTimerStyle = defaults.value(
            forKey: PreferenceKeys.menuBarTimerStyle,
            default: PreferenceDefaults.menuBarTimerStyle
        )
        // Every defaults write lands here, the durations included; only a style change alters
        // what the item draws.
        guard stored != timerStyle else { return }
        timerStyle = stored
        restart()
    }

    // MARK: - Drawing

    /// Read-only seams, so a test can assert on the item without holding the AppKit object.
    var anchorOrigin: CGPoint? { anchorWindow?.frame.origin }
    var itemScreenFrame: CGRect? {
        guard let button = statusItem.button else { return nil }
        return button.window?.convertToScreen(button.convert(button.bounds, to: nil))
    }
    var countdownText: String {
        statusItem.button?.attributedTitle.string.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private var displayStyle: CountdownDisplayStyle? {
        guard state.shouldShowTimeInMenuBar else { return nil }
        return timerStyle.countdownDisplayStyle
    }

    /// Everything a tick cannot change, so that a tick only assigns a string: the VoiceOver
    /// label, and whether the countdown shows at all.
    private func configure() {
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(String(localized: accessibilityLabel))

        guard displayStyle != nil else {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
            return
        }

        button.imagePosition = .imageLeading
    }

    private func render(at referenceDate: Date) {
        guard let style = displayStyle, let button = statusItem.button else { return }
        let text = " " + style.text(forRemaining: state.timeRemaining(at: referenceDate))
        button.attributedTitle = NSAttributedString(string: text, attributes: titleAttributes)
    }

    private var accessibilityLabel: LocalizedStringResource {
        switch state.mode {
        case .idle: .menuBarAccessibilityIdle
        case .running, .postponedWork: .menuBarAccessibilityRunning
        case .paused: .menuBarAccessibilityPaused
        case .resting, .awaitingReturn: .menuBarAccessibilityResting
        }
    }
}
