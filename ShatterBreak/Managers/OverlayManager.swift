import AppKit
import SwiftUI

/// One overlay window per lit display, kept in line with the displays as they come and go.
@MainActor
final class OverlayManager: BreakPresenting {
    /// What a display joining mid-break must match. Every later overlay is presented settled:
    /// the entrance belongs to the moment the break began.
    private struct Session {
        let id = UUID()
        let state: TimerState
        let effectType: EffectType
        /// The first capture of each display, so one that leaves and returns is restored to
        /// the desktop it left rather than re-captured through the lock screen.
        var captures: [CGDirectDisplayID: CGImage] = [:]
    }

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var overlayStates: [CGDirectDisplayID: OverlayPresentationState] = [:]
    private var captureTasks: [Task<Void, Never>] = []
    private var session: Session?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init() {
        // A display skipped because it was asleep has no window, and nothing else prompts a
        // recheck once it lights up.
        let workspace = NSWorkspace.shared.notificationCenter
        let triggers = [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification)
        ]
        observers = triggers.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcileOverlays() }
            })
        }
    }

    isolated deinit {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
    }

    private var defaults: UserDefaults { .standard }

    var selectedEffectType: EffectType {
        defaults.value(forKey: PreferenceKeys.effectType, default: PreferenceDefaults.effectType)
    }

    private var windowLevel: NSWindow.Level {
        let soft = defaults.object(forKey: PreferenceKeys.softOverlay) as? Bool ?? PreferenceDefaults.softOverlay
        return soft ? NSWindow.Level(NSWindow.Level.mainMenu.rawValue - 1) : .screenSaver
    }

    /// Shatter needs both consents settled: without Screen Recording there is nothing to
    /// fracture, and capturing on an unsettled direct-capture answer puts the system's dialog
    /// over the break. Fogged is the cheaper wrong outcome.
    nonisolated static func resolveEffectType(
        selected: EffectType,
        hasScreenRecordingPermission: Bool,
        directCaptureAccess: DirectCaptureAccess
    ) -> EffectType {
        guard selected.requiresScreenCapture else { return selected }
        guard hasScreenRecordingPermission, directCaptureAccess == .allowed else { return .fogged }
        return selected
    }

    // MARK: - BreakPresenting

    var presentedState: TimerState? { session?.state }

    var hasAwakeScreen: Bool { ScreenCapture.screens().contains(where: Self.isAwake) }

    /// A user on Fogged or Dimmed is never asked for anything.
    func prepareCapture() async {
        guard selectedEffectType.requiresScreenCapture else { return }
        await ScreenCapturePermissionManager.shared.prepareForCapture()
    }

    func show(_ state: TimerState, style: OverlayPresentationStyle) {
        dismiss()

        let permissions = ScreenCapturePermissionManager.shared
        let session = Session(
            state: state,
            effectType: Self.resolveEffectType(
                selected: selectedEffectType,
                hasScreenRecordingPermission: CGPreflightScreenCaptureAccess(),
                directCaptureAccess: permissions.directCaptureAccess
            )
        )
        self.session = session

        for screen in ScreenCapture.screens() where Self.isAwake(screen) {
            present(on: screen, settled: style == .settled)
        }
        if session.effectType == .shatter {
            startCapture(for: Set(overlayStates.keys))
        }
    }

    func dismiss() {
        captureTasks.forEach { $0.cancel() }
        captureTasks.removeAll()
        session = nil
        windows.keys.forEach(removeWindow)
        overlayStates.removeAll()
    }

    // MARK: - Displays changing mid-break

    /// Windows stay pinned to their own display. Planned against every attached display, not
    /// only lit ones, so one that merely sleeps does not read as removed.
    private func reconcileOverlays() {
        guard let session else { return }

        let plan = OverlayReconciliation.plan(
            currentWindows: windows.mapValues(\.frame),
            availableScreens: ScreenCapture.screens()
        )

        plan.removed.forEach(removeWindow)

        for screen in plan.reframed {
            windows[screen.displayID]?.setFrame(screen.frame, display: true)
            // Always from the pristine capture: re-fitting the one on screen would eat further
            // into the desktop each time.
            if let retained = session.captures[screen.displayID] {
                overlayStates[screen.displayID]?.backgroundImage = FreezeFrame.fitted(retained, to: screen.frame.size)
            }
        }

        var needingCapture: Set<CGDirectDisplayID> = []
        for screen in plan.added where Self.isAwake(screen) {
            present(on: screen, settled: true)
            if let retained = session.captures[screen.displayID] {
                overlayStates[screen.displayID]?.startShatter(with: FreezeFrame.fitted(retained, to: screen.frame.size))
            } else {
                needingCapture.insert(screen.displayID)
            }
        }

        // Fogged and dimmed render fully without a capture; only shatter must catch up, and
        // `startShatter` leaves displays already shattered alone.
        if session.effectType == .shatter {
            startCapture(for: needingCapture)
        }
    }

    // MARK: - Windows

    private static func isAwake(_ screen: ScreenInfo) -> Bool {
        CGDisplayIsAsleep(screen.displayID) == 0
    }

    private func present(on screen: ScreenInfo, settled: Bool) {
        guard let session else { return }
        let overlayState = OverlayPresentationState(effectType: session.effectType, settled: settled)
        let window = makeWindow(frame: screen.frame)
        window.contentView = NSHostingView(rootView: OverlayView(state: session.state, presentation: overlayState))
        window.makeKeyAndOrderFront(nil)

        overlayStates[screen.displayID] = overlayState
        windows[screen.displayID] = window
    }

    private func removeWindow(for displayID: CGDirectDisplayID) {
        windows[displayID]?.contentView = nil
        windows[displayID]?.orderOut(nil)
        windows[displayID] = nil
        overlayStates[displayID] = nil
    }

    private func makeWindow(frame: CGRect) -> NSWindow {
        // Non-activating, so a click on the overlay's buttons never takes keyboard focus from
        // the app the user was working in (issue #79).
        let window = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Panels hide when their app deactivates; this one must stay up for the whole break.
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.level = windowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        // Clear windows let clicks through by default; the break must catch them.
        window.ignoresMouseEvents = false
        window.setFrame(frame, display: true)
        return window
    }

    // MARK: - Capture

    /// Accumulates: a display joining mid-break may capture while another capture is in flight.
    private func startCapture(for displayIDs: Set<CGDirectDisplayID>) {
        guard displayIDs.isEmpty == false, let sessionID = session?.id else { return }
        captureTasks.append(Task(priority: .utility) { [weak self] in
            guard let images = try? await ScreenCapture.captureImages(displayIDs) else { return }
            self?.applyCapture(images, sessionID: sessionID)
        })
    }

    private func applyCapture(_ images: [CGDirectDisplayID: CGImage], sessionID: UUID) {
        // A capture that outlived its break must not paint the next one.
        guard session?.id == sessionID else { return }
        session?.captures.merge(images) { retained, _ in retained }
        // Displays the capture missed shatter over the fogged fallback.
        for (displayID, overlayState) in overlayStates {
            overlayState.startShatter(with: images[displayID])
        }
    }
}
