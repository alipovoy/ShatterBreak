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
    private var windows: [NSWindow] = []
    private var captureTask: Task<Void, Never>?  // Manages the asynchronous screen capture process
    
    private var selectedEffectType: EffectType {
        UserDefaults.standard.string(forKey: "effectType")
            .flatMap(EffectType.init(rawValue:)) ?? .shatter
    }

    func showOverlays(state: TimerState) {
        captureTask?.cancel()  // Cancel any ongoing capture tasks before starting a new one

        let hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        let shouldCaptureScreenshots = hasScreenRecordingPermission && selectedEffectType == .shatter

        captureTask = Task {
            do {
                let capturedImages = try await captureImages(shouldCaptureScreenshots)
                guard !Task.isCancelled else { return }

                // Create an overlay window for each screen
                for screen in NSScreen.screens {
                    let window = NSWindow(
                        contentRect: screen.frame,
                        styleMask: .borderless,
                        backing: .buffered,
                        defer: false
                    )

                    // Prevent AppKit from auto-releasing the window on close, as we manage its lifecycle
                    window.isReleasedWhenClosed = false

                    // Allow overlaying native fullscreen spaces
                    window.collectionBehavior = [
                        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
                    ]
                    // Determine window level based on "Soft Overlay" preference
                    let softOverlay = UserDefaults.standard.bool(forKey: "softOverlay")
                    if softOverlay {
                        window.level = NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1)  // Place below menu bar
                    } else {
                        window.level = .screenSaver  // Place above EVERYTHING
                    }

                    window.isOpaque = false
                    window.backgroundColor = .clear
                    window.ignoresMouseEvents = false  // Disallow clicks to pass through
                    window.setFrame(screen.frame, display: true)

                    let displayID =
                        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? CGDirectDisplayID ?? CGMainDisplayID()
                    let screenshot = capturedImages[displayID]

                    let hostingView = NSHostingView(
                        rootView: OverlayView(
                            state: state, bgImage: screenshot,
                            hasPermission: hasScreenRecordingPermission))
                    window.contentView = hostingView
                    window.makeKeyAndOrderFront(nil)

                    windows.append(window)
                }
            } catch is CancellationError {
                return
            } catch {
                print("ScreenCaptureKit error: \(error.localizedDescription)")
            }
        }
    }

    func dismissOverlays() {
        captureTask?.cancel()  // Cancel any pending capture tasks

        windows.forEach { window in
            // Safely detach the SwiftUI view and hide the window before deallocation
            window.contentView = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func captureImages(_ shouldCaptureScreenshots: Bool) async throws -> [
        CGDirectDisplayID: CGImage
    ] {
        guard shouldCaptureScreenshots else { return [:] }

        try Task.checkCancellation()
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)

        var capturedImages: [CGDirectDisplayID: CGImage] = [:]

        for display in shareableContent.displays {
            try Task.checkCancellation()

            let filter = SCContentFilter(
                display: display, excludingApplications: [], exceptingWindows: [])
            let config = screenshotConfiguration(for: display)
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            capturedImages[display.displayID] = cgImage
        }

        return capturedImages
    }

    private func screenshotConfiguration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        return config
    }
}
