import Foundation
import os

extension Logger {
    /// Falls back to the known identifier where `Bundle.main` has none, as under tests.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.lipovoy.shatterbreak"

    /// Failures the overlay's fallback would otherwise hide.
    static let capture = Logger(subsystem: subsystem, category: "ScreenCapture")
}
