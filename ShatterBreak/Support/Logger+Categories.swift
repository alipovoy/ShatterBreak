import Foundation
import os

extension Logger {
    /// Falls back to the known identifier where `Bundle.main` has none, as under tests.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.lipovoy.shatterbreak"

    /// Capture failures the overlay's fallback path would otherwise swallow.
    ///
    /// Console.app: `subsystem:dev.lipovoy.shatterbreak category:ScreenCapture`.
    static let capture = Logger(subsystem: subsystem, category: "ScreenCapture")
}
