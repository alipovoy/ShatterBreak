import AppKit
import SwiftUI

/// The status item and its popover. AppKit rather than `MenuBarExtra`, which drops font
/// modifiers on its label: without monospaced digits the item resized every tick.
///
/// The popover hangs off an anchor window, not the item: AppKit moves a popover whose
/// positioning view resizes.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let state: TimerState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    /// From the menu bar's own point size, read before `button.font` is touched, which keeps
    /// the baseline where AppKit put it.
    private let titleAttributes: [NSAttributedString.Key: Any]

    /// Parked where the item was when the menu opened, and left there.
    private var anchorWindow: NSWindow?

    /// Both read in ``press(menuIsShown:)``.
    private var dismissalIsUnanswered = false
    private var isClosing = false

    private var refreshTask: Task<Void, Never>?
    private var styleObserver: (any NSObjectProtocol)?
    private var timerStyle: MenuBarTimerStyle

    init(state: TimerState) {
        self.state = state
        self.timerStyle = state.defaults.value(
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

        styleObserver = NotificationCenter.default.addObserver(
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
            NotificationCenter.default.removeObserver(styleObserver)
        }
        anchorWindow?.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Popover

    enum PressOutcome {
        case swallowed, closes, opens
    }

    /// A click on the item dismisses the menu before the action runs, so the two are matched by
    /// order: a dismissal the item caused is followed by a press, one caused elsewhere is not.
    ///
    /// A press that dismissed nothing (VoiceOver, Full Keyboard Access) closes the menu itself.
    /// A menu still fading reads as shown, and is reopened rather than closed again.
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

        // Deprecated, but `activate()` declines to bring an accessory app forward, leaving the
        // menu with no key window.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)

        popover.contentViewController?.view.window?.makeKey()
        dropFirstResponder()
    }

    /// The duration field grabs first responder as the window appears. Dropped both here and at
    /// `didShow`: either alone misses a case.
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

    /// From the trailing edge, the one coordinate a status item keeps as its width changes.
    /// 16pt is where the icon sits with the countdown hidden.
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
        // Otherwise the anchor, and the menu with it, stays on the Space it first appeared on.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return window
    }

    // MARK: - Refresh

    /// No strong `self` across the await, so `deinit` can run while the loop sleeps. Configures
    /// inside the task so configuring and drawing read the same mode.
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

    /// `withObservationTracking` fires once, so the handler re-registers; registering anywhere
    /// else arms a second tracker for every one it adds.
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
        let stored: MenuBarTimerStyle = state.defaults.value(
            forKey: PreferenceKeys.menuBarTimerStyle,
            default: PreferenceDefaults.menuBarTimerStyle
        )
        // Every defaults write lands here; only a style change alters the item.
        guard stored != timerStyle else { return }
        timerStyle = stored
        restart()
    }

    // MARK: - Drawing

    /// For tests.
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

    /// What a tick cannot change, so a tick only assigns a string.
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
