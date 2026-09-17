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

    /// Intent rather than `NSPopover.isShown` — see ``clickOpensMenu(intendedOpen:popoverIsShown:)``.
    private var isMenuOpen = false

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

    @objc private func togglePopover() {
        guard Self.clickOpensMenu(intendedOpen: isMenuOpen, popoverIsShown: popover.isShown) else {
            isMenuOpen = false
            popover.performClose(nil)
            return
        }

        guard let anchor = stageAnchor() else { return }
        isMenuOpen = true

        // Deprecated, but the `activate()` that replaced it declines to bring an accessory
        // app forward — measured leaving the menu with no key window at all.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// The duration field otherwise takes first responder, being the first control in the
    /// menu that accepts one.
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    /// AppKit dismisses a transient popover on the mouse-down, and the button's action runs on
    /// the mouse-up — measured one event and 16ms later. Left alone, that close is
    /// indistinguishable here from one a click elsewhere caused, and answering it by reopening
    /// would make the item's own click flash the menu shut and back up. Refusing it hands the
    /// decision to the action, which is the only place that knows the click was on the item.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown,
              event.window === statusItem.button?.window else { return true }
        return false
    }

    /// Every close that got this far belongs to something other than the item's own click, so
    /// the intent it left behind is stale. Not `didClose`: that lands when the animation ends,
    /// ~530ms later, and a click inside it would still find both flags saying a menu is up.
    func popoverWillClose(_ notification: Notification) {
        isMenuOpen = false
    }

    /// Neither flag decides this alone: `isShown` stays true through the closing animation, so
    /// a quick second click would ask a closing menu to close again; and a show requested while
    /// one is still closing leaves `isShown` false with a menu on its way up.
    static func clickOpensMenu(intendedOpen: Bool, popoverIsShown: Bool) -> Bool {
        (intendedOpen && popoverIsShown) == false
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
