import Foundation
import AppKit
import CoreGraphics

@MainActor
@Observable
final class ScreenCapturePermissionManager {
    static let shared = ScreenCapturePermissionManager()

    enum Status {
        case granted
        case denied
        case notDetermined
    }

    private(set) var status: Status = .notDetermined

    private static let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private var observationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let appNotificationCenter: NotificationCenter

    init(
        defaults: UserDefaults = .standard,
        appNotificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.appNotificationCenter = appNotificationCenter
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
        defaults.set(true, forKey: Self.launchKey)
        CGRequestScreenCaptureAccess()
    }

    func requestNow() {
        CGRequestScreenCaptureAccess()
    }

    private var hasLaunchedBefore: Bool {
        defaults.bool(forKey: Self.launchKey)
    }

    private func observeAppActive() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in appNotificationCenter.notifications(
                named: NSApplication.didBecomeActiveNotification
            ) {
                self.refresh()
            }
        }
    }


    @MainActor
    deinit {
        observationTask?.cancel()
    }
}
