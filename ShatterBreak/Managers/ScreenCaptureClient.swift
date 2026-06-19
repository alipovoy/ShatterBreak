import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A seam over ScreenCaptureKit and AppKit used by ``OverlayManager`` to enumerate
/// displays, check screen-recording permission, and capture per-display
/// screenshots.
///
/// The ``live`` implementation wraps the real SC\* and `NSScreen` APIs, none of
/// which are constructible from a unit test (`SCShareableContent` has no public
/// initializer). Tests inject a double to drive the capture pipeline — partial
/// captures, total failures, and permission gating — deterministically.
struct ScreenCaptureClient: Sendable {
    /// Whether screen-recording permission is currently granted.
    var hasPermission: @MainActor @Sendable () -> Bool

    /// The displays currently available to present overlays on.
    var availableScreens: @MainActor @Sendable () -> [ScreenInfo]

    /// Captures a screenshot for each requested display.
    ///
    /// Displays whose individual capture fails are omitted from the result, so the
    /// caller falls back to a plain overlay for them. A total failure (for example,
    /// missing permission discovered late) returns an empty dictionary. Throws only
    /// `CancellationError` when the surrounding task is cancelled.
    var captureImages: @Sendable (Set<CGDirectDisplayID>) async throws -> [CGDirectDisplayID: CGImage]
}

extension ScreenCaptureClient {
    @MainActor
    static let live = Self(
        hasPermission: {
            CGPreflightScreenCaptureAccess()
        },
        availableScreens: {
            NSScreen.screens.map { screen in
                ScreenInfo(displayID: displayID(for: screen), frame: screen.frame)
            }
        },
        captureImages: { displayIDs in
            try await captureImages(displayIDs: displayIDs)
        }
    )

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    private static func captureImages(
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

    private static func excludedApplications(
        from shareableContent: SCShareableContent
    ) -> [SCRunningApplication] {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let currentBundleIdentifier = Bundle.main.bundleIdentifier

        return shareableContent.applications.filter { application in
            ScreenCaptureSelfFilter.isSelf(
                processID: application.processID,
                bundleIdentifier: application.bundleIdentifier,
                currentProcessID: currentProcessIdentifier,
                currentBundleIdentifier: currentBundleIdentifier
            )
        }
    }

    private static func screenshotConfiguration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        return config
    }
}
