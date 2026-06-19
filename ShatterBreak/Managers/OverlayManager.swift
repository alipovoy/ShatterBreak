import AppKit
import os
import SwiftUI

@MainActor
protocol OverlayManaging: AnyObject {
    func showOverlays(state: TimerState)
    func dismissOverlays()
}

@MainActor
class OverlayManager: OverlayManaging {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var overlayStates: [CGDirectDisplayID: OverlayPresentationState] = [:]
    private var captureTask: Task<Void, Never>?
    private var activeSessionID = UUID()

    private let defaults: UserDefaults
    private let captureClient: ScreenCaptureClient

    init(
        defaults: UserDefaults = .standard,
        captureClient: ScreenCaptureClient = .live
    ) {
        self.defaults = defaults
        self.captureClient = captureClient
    }

    /// The effect to present, derived from the user's preference. Defaults to
    /// `.shatter` when the stored value is missing or unrecognized.
    var selectedEffectType: EffectType {
        defaults.string(forKey: PreferenceKeys.effectType)
            .flatMap(EffectType.init(rawValue:)) ?? .shatter
    }

    /// Whether overlays use the softer, below-menu-bar window level. Defaults to
    /// `true` when the preference has never been set.
    var prefersSoftOverlay: Bool {
        defaults.object(forKey: PreferenceKeys.softOverlay) as? Bool ?? true
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

        for screen in captureClient.availableScreens() {
            let overlayState = OverlayPresentationState(
                effectType: effectType,
                allowsShatterUpgrade: shouldCaptureScreenshots
            )
            let window = makeWindow(frame: screen.frame)
            let hostingView = NSHostingView(
                rootView: OverlayView(state: state, presentation: overlayState)
            )

            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)

            overlayStates[screen.displayID] = overlayState
            windows[screen.displayID] = window
        }

        guard effectType == .shatter else { return }

        guard shouldCaptureScreenshots else {
            beginShatter(with: [:], sessionID: sessionID)
            return
        }

        let capture = captureClient.captureImages
        captureTask = Self.makeCaptureTask(
            sessionID: sessionID,
            displayIDs: Set(overlayStates.keys),
            capture: capture
        ) { [weak self] images, captureSessionID in
            self?.beginShatter(with: images, sessionID: captureSessionID)
        }
    }

    func dismissOverlays() {
        captureTask?.cancel()
        captureTask = nil
        activeSessionID = UUID()

        windows.values.forEach { window in
            // Safely detach the SwiftUI view and hide the window before deallocation
            window.contentView = nil
            window.orderOut(nil)
        }
        windows.removeAll()
        overlayStates.removeAll()
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
            do {
                let images = try await capture(displayIDs)
                await applyCapture(images, sessionID)
            } catch is CancellationError {
                return
            } catch {
                Logger.capture.error(
                    "Screen capture task failed; overlays remain plain: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
