import AppKit
import os
import ScreenCaptureKit

struct ScreenInfo: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
}

enum ScreenCapture {
    @MainActor
    static func screens() -> [ScreenInfo] {
        NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return ScreenInfo(displayID: displayID ?? CGMainDisplayID(), frame: screen.frame)
        }
    }

    /// One screenshot per display, without this app's own windows. A display whose capture
    /// fails is left out, so its overlay falls back; throws only on cancellation.
    static func captureImages(_ displayIDs: Set<CGDirectDisplayID>) async throws -> [CGDirectDisplayID: CGImage] {
        let content: SCShareableContent
        do {
            content = try await loadShareableContent()
        } catch {
            try Task.checkCancellation()
            let reason = error.localizedDescription
            Logger.capture.error("Failed to load shareable content: \(reason, privacy: .public)")
            return [:]
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { app in
            app.processID == ownPID || (ownBundleID != nil && app.bundleIdentifier == ownBundleID)
        }

        var images: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays where displayIDs.contains(display.displayID) {
            try Task.checkCancellation()
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            do {
                images[display.displayID] = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration(for: display)
                )
            } catch {
                try Task.checkCancellation()
                let reason = error.localizedDescription
                Logger.capture.error(
                    "Failed to capture display \(display.displayID, privacy: .public): \(reason, privacy: .public)"
                )
            }
        }
        try Task.checkCancellation()
        return images
    }

    /// Settles macOS's direct-capture consent at a moment of the app's choosing, by making
    /// the same request a capture makes: that request is where macOS raises its dialog.
    static func confirmDirectCaptureAccess() async -> Bool {
        do {
            _ = try await loadShareableContent()
            return true
        } catch {
            let reason = error.localizedDescription
            Logger.capture.error("Direct screen capture is not allowed: \(reason, privacy: .public)")
            return false
        }
    }

    private static func loadShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    /// At the display's native pixel size: `SCDisplay` measures in points, which halves the
    /// resolution on Retina.
    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        config.width = mode?.pixelWidth ?? display.width
        config.height = mode?.pixelHeight ?? display.height
        config.showsCursor = false
        return config
    }
}
