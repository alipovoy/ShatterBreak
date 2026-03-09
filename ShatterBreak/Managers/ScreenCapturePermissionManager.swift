import Foundation
import AppKit
import CoreGraphics

@MainActor
@Observable
final class ScreenCapturePermissionManager {
    enum Status {
        case granted
        case denied
        case notDetermined
    }

    private(set) var status: Status = .notDetermined

    private static let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private var observationTask: Task<Void, Never>?

    init() {
        requestPermissionIfFirstLaunch()
        refresh()
        observeAppActive()
    }

    func refresh() {
        if CGPreflightScreenCaptureAccess() {
            status = .granted
        } else {
            status = hasLaunchedBefore ? .denied : .notDetermined
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.launchKey)
    }

    private func requestPermissionIfFirstLaunch() {
        guard !hasLaunchedBefore else { return }
        UserDefaults.standard.set(true, forKey: Self.launchKey)
        CGRequestScreenCaptureAccess()
    }

    private func observeAppActive() {
        observationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.refresh()
            }
        }
    }
}
