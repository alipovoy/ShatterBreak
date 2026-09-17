import AppKit
import SwiftUI

/// The status item — the icon, and a countdown beside it while a session runs — and the
/// popover holding ``MenuView``.
///
/// AppKit rather than `MenuBarExtra`: that scene discards every font modifier on its label,
/// so the countdown drew in the menu bar's proportional-digit font and the item resized on
/// every tick, shuffling the status icons to its left. Monospaced digits hold the width for
/// as long as the digit count holds.
///
/// The item sizes itself to whatever it draws. The popover is the one thing placed by hand,
/// and only once per opening: AppKit moves a popover whose positioning view resizes, and
/// lands it half a countdown away, so it hangs off an anchor that holds still instead.
@MainActor
final class MenuBarController: NSObject {
    private let state: TimerState
    private let defaults: any KeyValueStore
    private let notificationCenter: NotificationCenter
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    /// Built from the menu bar's own point size, read before anything overrides
    /// `button.font`, which is what keeps the baseline where AppKit put it.
    private let titleAttributes: [NSAttributedString.Key: Any]

    /// A 1×1 invisible window parked where the button was when the menu was opened. The
    /// popover hangs off this instead of the button, so the item resizing behind it — which
    /// is what AppKit reacts to — cannot reach the menu.
    private var anchorWindow: NSWindow?

    /// Whether the menu is meant to be up, which is not the same as `NSPopover.isShown`:
    /// that stays true through the closing animation, so a quick second click read it as
    /// still open and asked it to close again — swallowing the click.
    private var isMenuOpen = false

    private var refreshTask: Task<Void, Never>?
    private var styleObserver: (any NSObjectProtocol)?
    private var closeObserver: (any NSObjectProtocol)?
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
        popover.contentViewController = NSHostingController(rootView: MenuView(state: state))

        styleObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.styleDidChange() }
        }

        // `NSPopover` posts to the default centre, not the injected one. A transient popover
        // also closes on a click elsewhere, which never reaches `togglePopover`.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.popoverDidClose() }
        }

        observeState()
        restart()
    }

    isolated deinit {
        refreshTask?.cancel()
        if let styleObserver {
            notificationCenter.removeObserver(styleObserver)
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        anchorWindow?.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        guard Self.clickOpensMenu(intendedOpen: isMenuOpen, popoverIsShown: popover.isShown) else {
            isMenuOpen = false
            popover.performClose(nil)
            return
        }
        isMenuOpen = true

        // An accessory app's popover would otherwise open behind the frontmost app, leaving
        // the duration fields unable to take a keystroke.
        NSApp.activate(ignoringOtherApps: true)

        if let anchor = stageAnchor() {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Whether a click on the icon opens the menu, rather than closing the one that is up.
    ///
    /// Neither flag decides this alone. `NSPopover.isShown` stays true through the closing
    /// animation, so a quick second click reads a menu that is on its way out as still open
    /// and asks it to close again — the click goes nowhere. And a transient popover
    /// dismissed by a click elsewhere never runs this code, leaving the intent set, so the
    /// next click would close a menu that has already gone.
    static func clickOpensMenu(intendedOpen: Bool, popoverIsShown: Bool) -> Bool {
        (intendedOpen && popoverIsShown) == false
    }

    /// A close landing after the menu was opened again is the old one arriving late: the
    /// anchor beneath it belongs to the new menu, and taking it down would take the menu
    /// with it. `isShown` cannot tell the two apart at this point — it reads false either
    /// way — so the anchor is only taken down for a close the button asked for, and is
    /// otherwise left parked, invisible, for the next opening to reuse.
    private func popoverDidClose() {
        guard isMenuOpen == false else { return }
        anchorWindow?.orderOut(nil)
    }

    /// Measured from the trailing edge, the one coordinate a status item keeps when its
    /// width changes. Taken from the centre instead, an anchor ends up beside the item
    /// rather than on it when a session is stopped from an open menu. Sixteen points is
    /// where the icon sits while the countdown is hidden.
    private static let anchorInsetFromTrailingEdge: CGFloat = 16

    /// Parks the anchor over the item's screen position as it stands right now, and hands
    /// back the view for the popover to hang off.
    func stageAnchor() -> NSView? {
        guard let button = statusItem.button,
              let screenRect = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) else {
            return nil
        }

        let origin = NSPoint(x: screenRect.maxX - Self.anchorInsetFromTrailingEdge, y: screenRect.minY)
        if let anchorWindow {
            anchorWindow.setFrameOrigin(origin)
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: origin, size: CGSize(width: 1, height: 1)),
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
            anchorWindow = window
        }

        anchorWindow?.orderFront(nil)
        return anchorWindow?.contentView
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
        button.attributedTitle = attributedTitle(style.text(forRemaining: state.timeRemaining(at: referenceDate)))
    }

    private func attributedTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: " " + text, attributes: titleAttributes)
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
