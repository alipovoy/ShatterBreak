import AppKit
import ScreenCaptureKit
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
    
    private var selectedEffectType: EffectType {
        UserDefaults.standard.string(forKey: PreferenceKeys.effectType)
            .flatMap(EffectType.init(rawValue:)) ?? .shatter
    }

    func showOverlays(state: TimerState) {
        dismissOverlays()

        let hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        let effectType = selectedEffectType
        let shouldCaptureScreenshots = hasScreenRecordingPermission && effectType == .shatter
        let sessionID = UUID()
        activeSessionID = sessionID

        for screen in NSScreen.screens {
            let displayID = displayID(for: screen)
            let overlayState = OverlayPresentationState(
                effectType: effectType,
                allowsShatterUpgrade: shouldCaptureScreenshots
            )
            let window = makeWindow(for: screen)
            let hostingView = NSHostingView(
                rootView: OverlayView(state: state, presentation: overlayState)
            )

            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)

            overlayStates[displayID] = overlayState
            windows[displayID] = window
        }

        guard effectType == .shatter else { return }

        guard shouldCaptureScreenshots else {
            beginShatter(with: [:], sessionID: sessionID)
            return
        }

        captureTask = Self.makeCaptureTask(
            sessionID: sessionID,
            displayIDs: Set(overlayStates.keys)
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
        guard sessionID == activeSessionID else { return }

        for (displayID, overlayState) in overlayStates {
            overlayState.startShatter(with: images[displayID])
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Prevent AppKit from auto-releasing the window on close, as we manage its lifecycle.
        window.isReleasedWhenClosed = false

        // Allow overlaying native fullscreen spaces.
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]

        let softOverlay =
            UserDefaults.standard.object(forKey: PreferenceKeys.softOverlay) as? Bool ?? true
        if softOverlay {
            window.level = NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1)
        } else {
            window.level = .screenSaver
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.setFrame(screen.frame, display: true)
        return window
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    nonisolated private static func makeCaptureTask(
        sessionID: UUID,
        displayIDs: Set<CGDirectDisplayID>,
        applyCapture: @escaping @MainActor @Sendable ([CGDirectDisplayID: CGImage], UUID) -> Void
    ) -> Task<Void, Never> {
        Task(priority: .utility) {
            do {
                let images = try await captureImages(displayIDs: displayIDs)
                await applyCapture(images, sessionID)
            } catch {
                return
            }
        }
    }

    nonisolated private static func captureImages(
        displayIDs: Set<CGDirectDisplayID>
    ) async throws -> [CGDirectDisplayID: CGImage] {
        guard displayIDs.isEmpty == false else { return [:] }

        try Task.checkCancellation()
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return [:]
        }

        let excludedApplications = excludedApplications(from: shareableContent)

        var capturedImages: [CGDirectDisplayID: CGImage] = [:]

        for display in shareableContent.displays where displayIDs.contains(display.displayID) {
            try Task.checkCancellation()

            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let config = screenshotConfiguration(for: display)

            do {
                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                try Task.checkCancellation()
                capturedImages[display.displayID] = cgImage
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        return capturedImages
    }

    nonisolated private static func excludedApplications(
        from shareableContent: SCShareableContent
    ) -> [SCRunningApplication] {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let currentBundleIdentifier = Bundle.main.bundleIdentifier

        return shareableContent.applications.filter { application in
            if application.processID == currentProcessIdentifier {
                return true
            }

            guard let currentBundleIdentifier else { return false }
            return application.bundleIdentifier == currentBundleIdentifier
        }
    }

    nonisolated private static func screenshotConfiguration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        return config
    }
}
