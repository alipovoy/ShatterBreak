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

    func requestIfFirstLaunch() {
        guard !hasLaunchedBefore else { return }
        UserDefaults.standard.set(true, forKey: Self.launchKey)
        CGRequestScreenCaptureAccess()
    }

    func requestNow() {
        CGRequestScreenCaptureAccess()
    }

    private var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.launchKey)
    }

    private func observeAppActive() {
        observationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await MainActor.run { self?.refresh() }
            }
        }
    }


    @MainActor
    deinit {
        observationTask?.cancel()
    }
}
