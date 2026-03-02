import SwiftUI
import AppKit
import ScreenCaptureKit

@MainActor
class OverlayManager {
    private var windows: [NSWindow] = []
    private var captureTask: Task<Void, Never>? // Manages the asynchronous screen capture process

    func showOverlays(state: TimerState) {
        captureTask?.cancel() // Cancel any ongoing capture tasks before starting a new one

        let hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        captureTask = Task {
            var capturedImages: [CGDirectDisplayID: CGImage] = [:]

            if hasScreenRecordingPermission {
                do {
                    // Capture content from all displays, excluding desktop windows
                    let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

                    for display in shareableContent.displays {
                        if Task.isCancelled { return }

                        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = display.width
                        config.height = display.height
                        config.showsCursor = false

                        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        capturedImages[display.displayID] = cgImage
                    }
                } catch {
                    print("ScreenCaptureKit error: \(error.localizedDescription)")
                }
            }

            if Task.isCancelled { return } // Check for cancellation before creating windows

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
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                // Place above EVERYTHING (including full-screen games, videos, and presentation modes)
                window.level = .screenSaver

                window.isOpaque = false
                window.backgroundColor = .clear
                window.ignoresMouseEvents = false // Disallow clicks to pass through
                window.setFrame(screen.frame, display: true)

                let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
                let screenshot = capturedImages[displayID]

                let hostingView = NSHostingView(rootView: OverlayView(state: state, bgImage: screenshot, hasPermission: hasScreenRecordingPermission))
                window.contentView = hostingView
                window.makeKeyAndOrderFront(nil)

                windows.append(window)
            }
        }
    }

    func dismissOverlays() {
        captureTask?.cancel() // Cancel any pending capture tasks

        windows.forEach { window in
            // Safely detach the SwiftUI view and hide the window before deallocation
            window.contentView = nil
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}
