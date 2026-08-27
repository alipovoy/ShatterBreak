import AppKit
import SwiftUI

@MainActor
final class OverlayManager {
    /// The decisions made when a break began, retained so that overlays added for a
    /// display that appears mid-break (e.g. a clamshell lid opening) match the rest.
    /// The entrance style is deliberately absent: a session exists only after the
    /// entrance has played, so every later overlay is presented settled.
    private struct ActiveSession {
        let id: UUID
        let state: TimerState
        let effectType: EffectType

        /// The freeze-frame taken for each display as the break began, kept for the
        /// break's duration so a display that leaves and returns is restored to the
        /// desktop it left rather than re-captured. Costs nothing extra
        /// while a display is present: its overlay is showing this very image.
        var captures: [CGDirectDisplayID: CGImage] = [:]
    }

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    /// Internal (not `private`) so tests can assert how each display is presented.
    private(set) var overlayStates: [CGDirectDisplayID: OverlayPresentationState] = [:]
    /// Internal (not `private`) so tests can await the captures still in flight.
    private(set) var captureTasks: [Task<Void, Never>] = []
    private var activeSessionID = UUID()
    private var session: ActiveSession?

    private let defaults: any KeyValueStore
    private let captureClient: ScreenCaptureClient
    private let screenObserver: ScreenParametersObserver
    private let directCaptureAccess: @MainActor () -> DirectCaptureAccess

    /// - Parameter directCaptureAccess: the app's latest reading of macOS's direct-capture
    ///   consent, supplied by ``OverlayPresenter/live(defaults:)``. Defaults to
    ///   ``DirectCaptureAccess/unknown``, so a caller that never wires it up falls back to
    ///   fogged rather than putting a system dialog over the break.
    init(
        defaults: any KeyValueStore = UserDefaults.standard,
        captureClient: ScreenCaptureClient = .live,
        notificationCenter: NotificationCenter = .default,
        directCaptureAccess: @escaping @MainActor () -> DirectCaptureAccess = { .unknown }
    ) {
        self.defaults = defaults
        self.captureClient = captureClient
        self.screenObserver = ScreenParametersObserver(notificationCenter: notificationCenter)
        self.directCaptureAccess = directCaptureAccess

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

    /// Resolves the effect actually presented from the user's selection and the
    /// current permission state.
    ///
    /// ``EffectType/shatter`` needs Screen Recording permission to capture the screen;
    /// without it the break falls back to ``EffectType/fogged`` — fogged glass over
    /// the live desktop with cracks — instead of an empty shatter with nothing to
    /// fracture. Every other selection is presented as chosen.
    ///
    /// ``DirectCaptureAccess`` downgrades for a second reason: capturing without a settled
    /// answer raises the system's dialog on top of the overlay. Only
    /// ``DirectCaptureAccess/allowed`` proceeds, so a break arriving before the probe has
    /// answered renders fogged — the cheaper of the two wrong outcomes.
    static func resolveEffectType(
        selected: EffectType,
        hasScreenRecordingPermission: Bool,
        directCaptureAccess: DirectCaptureAccess = .unknown
    ) -> EffectType {
        guard selected.requiresScreenCapture else { return selected }
        guard hasScreenRecordingPermission, directCaptureAccess == .allowed else {
            return .fogged
        }
        return selected
    }

    /// The timer whose break is on screen, or `nil` when nothing is presented.
    ///
    /// Exists so that a caller sharing this manager can tell whether the window is still
    /// the one it put up before taking it down.
    var presentedState: TimerState? { session?.state }

    func showOverlays(state: TimerState, settled: Bool) {
        dismissOverlays()

        let effectType = Self.resolveEffectType(
            selected: selectedEffectType,
            hasScreenRecordingPermission: captureClient.hasPermission(),
            directCaptureAccess: directCaptureAccess()
        )
        let sessionID = UUID()
        activeSessionID = sessionID
        session = ActiveSession(id: sessionID, state: state, effectType: effectType)

        for screen in captureClient.availableScreens() {
            presentOverlay(for: screen, state: state, effectType: effectType, settled: settled)
        }

        // Only the shatter effect captures the screen. A resolved `.shatter` always
        // has permission (`resolveEffectType` downgrades to `.fogged` otherwise), so
        // a failed or partial capture falls back per-display to the live fogged
        // desktop rather than an empty shatter.
        guard effectType == .shatter else { return }

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
    /// active: a main display unplugged, a clamshell lid opened, or a display
    /// changing resolution. Each window stays pinned to its own display — overlays are
    /// never moved — so a vanished display's window is torn down, a new display gains its
    /// own overlay (and freeze-frame), and a resized display's window is reframed so its
    /// "I'm back" button stays reachable.
    ///
    /// Both branches draw on the session's retained captures rather than the screen as
    /// it looks now, so the freeze-frame keeps showing the desktop the break began over.
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

            // The overlay stretches its freeze-frame to fill the window, so a display
            // that changed shape would distort its own desktop. Re-fit the session's
            // pristine capture — never the cropped image already on screen — to the
            // new proportions.
            if let retained = session.captures[screen.displayID] {
                overlayStates[screen.displayID]?.backgroundImage = FreezeFrame.fitted(
                    retained,
                    to: screen.frame.size
                )
            }
        }

        guard plan.added.isEmpty == false else { return }

        var displaysNeedingCapture: Set<CGDirectDisplayID> = []
        for screen in plan.added {
            // Settled: the shake and glass sound belong to the moment the break began.
            // A display joining later catches up silently — including one that dropped
            // off while the screen slept and came back on wake.
            presentOverlay(
                for: screen,
                state: session.state,
                effectType: session.effectType,
                settled: true
            )

            // Holding a capture for a display is what marks it as one that left and came
            // back, so it is restored from that capture. Capturing now would freeze
            // whatever it returned through, typically the lock screen. A
            // display genuinely connected mid-break has nothing retained, and captures.
            guard let retained = session.captures[screen.displayID] else {
                displaysNeedingCapture.insert(screen.displayID)
                continue
            }

            overlayStates[screen.displayID]?.startShatter(
                with: FreezeFrame.fitted(retained, to: screen.frame.size)
            )
        }

        // Overlays no retained capture covered start in the `.plain` phase; the
        // shatter effect must catch them up. `startCapture` paints only the
        // still-`.plain` displays — already-shattered overlays are left untouched by
        // `startShatter`'s phase guard — so existing displays never re-shatter. The
        // fogged and dimmed effects need no catch-up: their overlays render fully from
        // the `.plain` phase, so a freshly added display matches the rest on its own.
        guard session.effectType == .shatter else { return }

        startCapture(for: displaysNeedingCapture, sessionID: session.id)
    }

    private func beginShatter(
        with images: [CGDirectDisplayID: CGImage],
        sessionID: UUID
    ) {
        // A capture that outlived its session must neither paint a later break's
        // overlays nor be retained as that break's freeze-frame.
        guard sessionID == activeSessionID else { return }

        // Keep the first capture each display produced: it is the one taken as the break
        // began, and the one a returning display must be restored to.
        session?.captures.merge(images) { retained, _ in retained }

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
    /// ``dismissOverlays()`` (or a newer ``showOverlays(state:settled:)``) rotated
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
    private func presentOverlay(
        for screen: ScreenInfo,
        state: TimerState,
        effectType: EffectType,
        settled: Bool
    ) {
        let overlayState = OverlayPresentationState(effectType: effectType, settled: settled)
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
        // A non-activating panel so overlay button clicks never activate this app
        // and steal keyboard focus from the app the user was working in.
        let window = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Prevent AppKit from auto-releasing the window on close, as we manage its lifecycle.
        window.isReleasedWhenClosed = false

        // Panels hide when their app deactivates by default; the overlay must stay
        // up while another app remains active for the whole break.
        window.hidesOnDeactivate = false

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
