import AppKit
import SwiftUI

/// The status item — a fixed-width countdown beside the icon — and the popover holding
/// ``MenuView``.
///
/// AppKit rather than `MenuBarExtra`: that scene discards every font and layout modifier on
/// its label, so the countdown drew in the menu bar's proportional-digit font and the item
/// resized on every tick, shuffling the status icons to its left.
@MainActor
final class MenuBarController: NSObject {
    private let state: TimerState
    private let defaults: any KeyValueStore
    private let notificationCenter: NotificationCenter
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    /// Built from the menu bar's own point size, read before anything overrides
    /// `button.font`, which is what keeps the baseline where AppKit put it.
    private let titleAttributes: [NSAttributedString.Key: Any]

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
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // An accessory app's popover would otherwise open behind the frontmost app, leaving
        // the duration fields unable to take a keystroke.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Refresh

    private func restart() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.drive() }
    }

    /// Configures inside the task rather than at the call site: the two must read the same
    /// mode, and by the time the task body runs the state that triggered it may have moved on.
    private func drive() async {
        configure()

        guard let style = displayStyle else { return }
        await style.driveCountdown(for: state) { [weak self] referenceDate in
            self?.render(at: referenceDate)
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

    private var displayStyle: CountdownDisplayStyle? {
        guard state.shouldShowTimeInMenuBar else { return nil }
        return timerStyle.countdownDisplayStyle
    }

    /// Everything a tick cannot change, so that a tick only assigns a string: the VoiceOver
    /// label, whether the countdown shows at all, and the width it is pinned to.
    private func configure() {
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(String(localized: accessibilityLabel))

        guard let style = displayStyle else {
            button.attributedTitle = NSAttributedString()
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.variableLength
            return
        }

        button.imagePosition = .imageLeading
        statusItem.length = length(fitting: style.widthCandidates(overDuration: state.countdownDuration), on: button)
    }

    private func render(at referenceDate: Date) {
        guard let style = displayStyle, let button = statusItem.button else { return }
        button.attributedTitle = attributedTitle(style.text(forRemaining: state.timeRemaining(at: referenceDate)))
    }

    private func attributedTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: " " + text, attributes: titleAttributes)
    }

    /// Measured by fitting the button to each candidate rather than summing metrics: only
    /// AppKit knows the padding it puts around the image and title.
    private func length(fitting candidates: [String], on button: NSStatusBarButton) -> CGFloat {
        var widest: CGFloat = 0
        for candidate in candidates {
            button.attributedTitle = attributedTitle(candidate)
            button.sizeToFit()
            widest = max(widest, button.frame.width)
        }
        return widest.rounded(.up)
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
