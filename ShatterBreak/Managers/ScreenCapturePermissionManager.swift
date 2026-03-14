import Foundation
import AppKit

@MainActor
@Observable
final class ScreenCapturePermissionManager {
    static let shared = ScreenCapturePermissionManager()

    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
    }

    private(set) var status: Status = .notDetermined

    private static let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private var observationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let appNotificationCenter: NotificationCenter
    private let permissionClient: ScreenCapturePermissionClient

    init(
        defaults: UserDefaults = .standard,
        appNotificationCenter: NotificationCenter = .default,
        permissionClient: ScreenCapturePermissionClient = .live
    ) {
        self.defaults = defaults
        self.appNotificationCenter = appNotificationCenter
        self.permissionClient = permissionClient
        refresh()
        observeAppActive()
    }

    func refresh() {
        if permissionClient.preflightAccess() {
            status = .granted
        } else {
            status = hasLaunchedBefore ? .denied : .notDetermined
        }
    }

    func openSystemSettings() {
        permissionClient.openSystemSettings()
    }

    func requestIfFirstLaunch() {
        guard !hasLaunchedBefore else { return }
        defaults.set(true, forKey: Self.launchKey)
        _ = permissionClient.requestAccess()
    }

    func requestNow() {
        _ = permissionClient.requestAccess()
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
