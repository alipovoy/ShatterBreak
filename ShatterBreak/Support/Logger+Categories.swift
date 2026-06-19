import Foundation
import os

extension Logger {
    /// Subsystem shared by all of ShatterBreak's loggers, falling back to the
    /// known bundle identifier when `Bundle.main` has none (for example, under tests).
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.lipovoy.shatterbreak"

    /// Logs screen-capture pipeline events: permission gating and ScreenCaptureKit
    /// failures that would otherwise be swallowed by the overlay fallback path.
    ///
    /// Filter in Console.app with `subsystem:dev.lipovoy.shatterbreak category:ScreenCapture`.
    static let capture = Logger(subsystem: subsystem, category: "ScreenCapture")
}
