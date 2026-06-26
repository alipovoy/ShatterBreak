import AppKit
import SwiftUI

@MainActor
final class OverlayManager {
    /// The decisions made when a break began, retained so that overlays added for a
    /// display that appears mid-break (e.g. a clamshell lid opening) match the rest.
    private struct ActiveSession {
        let id: UUID
        let state: TimerState
        let effectType: EffectType
        let shouldCaptureScreenshots: Bool
    }

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var overlayStates: [CGDirectDisplayID: OverlayPresentationState] = [:]
    private var captureTasks: [Task<Void, Never>] = []
    private var activeSessionID = UUID()
    private var session: ActiveSession?

    private let defaults: any KeyValueStore
    private let captureClient: ScreenCaptureClient
    private let screenObserver: ScreenParametersObserver

    init(
        defaults: any KeyValueStore = UserDefaults.standard,
        captureClient: ScreenCaptureClient = .live,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.captureClient = captureClient
        self.screenObserver = ScreenParametersObserver(notificationCenter: notificationCenter)

        screenObserver.startObserving { [weak self] in
            self?.reconcileOverlays()
        }
    }

    /// The effect to present, derived from the user's preference. Defaults to
    /// `.shatter` when the stored value is missing or unrecognized.
    var selectedEffectType: EffectType {
        defaults.string(forKey: PreferenceKeys.effectType)
            .flatMap(EffectType.init(rawValue:)) ?? PreferenceDefaults.effectType
    }

    /// Whether overlays use the softer, below-menu-bar window level. Defaults to
    /// `true` when the preference has never been set.
    var prefersSoftOverlay: Bool {
        defaults.object(forKey: PreferenceKeys.softOverlay) as? Bool ?? PreferenceDefaults.softOverlay
    }

    /// The window level overlays are presented at, derived from ``prefersSoftOverlay``.
    var overlayWindowLevel: NSWindow.Level {
        prefersSoftOverlay
            ? NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1)
            : .screenSaver
    }

    func showOverlays(state: TimerState) {
        dismissOverlays()

        let hasScreenRecordingPermission = captureClient.hasPermission()
        let effectType = selectedEffectType
        let shouldCaptureScreenshots = hasScreenRecordingPermission && effectType == .shatter
        let sessionID = UUID()
        activeSessionID = sessionID
        session = ActiveSession(
            id: sessionID,
            state: state,
            effectType: effectType,
            shouldCaptureScreenshots: shouldCaptureScreenshots
        )

        for screen in captureClient.availableScreens() {
            presentOverlay(for: screen, state: state, effectType: effectType)
        }

        guard effectType == .shatter else { return }

        guard shouldCaptureScreenshots else {
            beginShatter(with: [:], sessionID: sessionID)
            return
        }

        startCapture(for: Set(overlayStates.keys), sessionID: sessionID)
    }

    func dismissOverlays() {
        captureTasks.forEach { $0.cancel() }
        captureTasks.removeAll()
        activeSessionID = UUID()
        session = nil

        windows.keys.forEach(removeWindow(for:))
        windows.removeAll()
        overlayStates.removeAll()
    }

    /// Brings the live overlays back in line with the displays now attached.
    ///
    /// Invoked when the system reports a display-configuration change while a break is
    /// active (issue #3): a main display unplugged, a clamshell lid opened, or a display
    /// changing resolution. Each window stays pinned to its own display — overlays are
    /// never moved — so a vanished display's window is torn down, a new display gains its
    /// own overlay (and freeze-frame), and a resized display's window is reframed so its
    /// "I'm back" button stays reachable.
    func reconcileOverlays() {
        guard let session else { return }

        let plan = OverlayReconciliation.plan(
            currentWindows: windows.mapValues(\.frame),
            availableScreens: captureClient.availableScreens()
        )

        guard plan.isEmpty == false else { return }

        plan.removed.forEach(removeWindow(for:))
        for displayID in plan.removed {
            windows[displayID] = nil
            overlayStates[displayID] = nil
        }

        for screen in plan.reframed {
            windows[screen.displayID]?.setFrame(screen.frame, display: true)
        }

        guard plan.added.isEmpty == false else { return }

        var addedDisplayIDs: Set<CGDirectDisplayID> = []
        for screen in plan.added {
            presentOverlay(for: screen, state: session.state, effectType: session.effectType)
            addedDisplayIDs.insert(screen.displayID)
        }

        // Newly added overlays start in the `.plain` phase; the shatter effect must
        // catch them up. `beginShatter`/`startCapture` paint only the still-`.plain`
        // displays — already-shattered overlays are left untouched by `startShatter`'s
        // phase guard — so existing displays never re-shatter.
        guard session.effectType == .shatter else { return }

        guard session.shouldCaptureScreenshots else {
            beginShatter(with: [:], sessionID: session.id)
            return
        }

        startCapture(for: addedDisplayIDs, sessionID: session.id)
    }

    private func beginShatter(
        with images: [CGDirectDisplayID: CGImage],
        sessionID: UUID
    ) {
        Self.applyCapturedImages(
            images,
            sessionID: sessionID,
            activeSessionID: activeSessionID,
            to: overlayStates
        )
    }

    /// Paints captured screenshots onto their matching overlays, dropping any
    /// capture whose session no longer matches the active one.
    ///
    /// The session guard protects against a capture that finishes after
    /// ``dismissOverlays()`` (or a newer ``showOverlays(state:)``) rotated
    /// ``activeSessionID``: a stale image must never be painted onto the windows
    /// of a later session. Displays missing from `images` fall back to a plain
    /// overlay because ``OverlayPresentationState/startShatter(with:)`` accepts a
    /// `nil` background.
    static func applyCapturedImages(
        _ images: [CGDirectDisplayID: CGImage],
        sessionID: UUID,
        activeSessionID: UUID,
        to overlayStates: [CGDirectDisplayID: OverlayPresentationState]
    ) {
        guard sessionID == activeSessionID else { return }

        for (displayID, overlayState) in overlayStates {
            overlayState.startShatter(with: images[displayID])
        }
    }

    /// Builds an overlay window for `screen`, hosts an ``OverlayView`` on it, shows it,
    /// and registers both the window and its presentation state by display ID.
    private func presentOverlay(for screen: ScreenInfo, state: TimerState, effectType: EffectType) {
        let overlayState = OverlayPresentationState(effectType: effectType)
        let window = makeWindow(frame: screen.frame)
        let hostingView = NSHostingView(
            rootView: OverlayView(state: state, presentation: overlayState)
        )

        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        overlayStates[screen.displayID] = overlayState
        windows[screen.displayID] = window
    }

    /// Detaches the SwiftUI view and hides the window for a single display before it is
    /// deallocated. The caller is responsible for removing the dictionary entries.
    private func removeWindow(for displayID: CGDirectDisplayID) {
        guard let window = windows[displayID] else { return }
        window.contentView = nil
        window.orderOut(nil)
    }

    /// Starts a background screenshot capture for `displayIDs` and tracks the task so it
    /// can be cancelled on dismissal. Multiple captures may be in flight at once when a
    /// display appears mid-break, so tasks accumulate rather than replace one another.
    private func startCapture(for displayIDs: Set<CGDirectDisplayID>, sessionID: UUID) {
        guard displayIDs.isEmpty == false else { return }

        let capture = captureClient.captureImages
        let task = Self.makeCaptureTask(
            sessionID: sessionID,
            displayIDs: displayIDs,
            capture: capture
        ) { [weak self] images, captureSessionID in
            self?.beginShatter(with: images, sessionID: captureSessionID)
        }
        captureTasks.append(task)
    }

    private func makeWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Prevent AppKit from auto-releasing the window on close, as we manage its lifecycle.
        window.isReleasedWhenClosed = false

        // Allow overlaying native fullscreen spaces.
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
        ]

        window.level = overlayWindowLevel

        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.setFrame(frame, display: true)
        return window
    }

    nonisolated private static func makeCaptureTask(
        sessionID: UUID,
        displayIDs: Set<CGDirectDisplayID>,
        capture: @escaping @Sendable (Set<CGDirectDisplayID>) async throws -> [CGDirectDisplayID: CGImage],
        applyCapture: @escaping @MainActor @Sendable ([CGDirectDisplayID: CGImage], UUID) -> Void
    ) -> Task<Void, Never> {
        Task(priority: .utility) {
            // `capture` only throws `CancellationError` (its contract swallows and
            // logs every other failure at the source), so cancellation is the only
            // thing to catch here — nothing to diagnose.
            do {
                let images = try await capture(displayIDs)
                await applyCapture(images, sessionID)
            } catch {
                return
            }
        }
    }
}
