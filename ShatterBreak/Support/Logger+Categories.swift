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

    /// Logs timer stalls the user had to reset by hand.
    ///
    /// Only the reset is recorded, never the routine sleep deferrals around it: a deferral
    /// fires on every sleep that outlasts the countdown, so logging those would bury the
    /// one event that matters. The menu warning is the primary signal (issue #87's family
    /// is rare enough that a dismissable prompt beats a log nobody thinks to open); this
    /// keeps a timestamped trace for occurrences dismissed and forgotten (issue #89).
    ///
    /// Filter in Console.app with `subsystem:dev.lipovoy.shatterbreak category:Timer`.
    static let timer = Logger(subsystem: subsystem, category: "Timer")
}
