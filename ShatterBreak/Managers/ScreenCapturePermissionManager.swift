import Foundation

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
    private var appActiveObserver: AppActiveObserver?
    private let defaults: any KeyValueStore
    private let appNotificationCenter: NotificationCenter
    private let permissionClient: ScreenCapturePermissionClient

    init(
        defaults: any KeyValueStore = UserDefaults.standard,
        appNotificationCenter: NotificationCenter = .default,
        permissionClient: ScreenCapturePermissionClient = .live
    ) {
        self.defaults = defaults
        self.appNotificationCenter = appNotificationCenter
        self.permissionClient = permissionClient
        refresh()
    }

    func refresh() {
        if permissionClient.preflightAccess() {
            status = .granted
        } else {
            status = hasLaunchedBefore ? .denied : .notDetermined
        }

        updateAppActiveObservation()
    }

    func openSystemSettings() {
        permissionClient.openSystemSettings()
    }

    func requestIfFirstLaunch() {
        guard !hasLaunchedBefore else { return }
        defaults.set(true, forKey: Self.launchKey)
        updateAppActiveObservation()
        _ = permissionClient.requestAccess()
    }

    private var hasLaunchedBefore: Bool {
        defaults.bool(forKey: Self.launchKey)
    }

    private func updateAppActiveObservation() {
        guard status != .granted else {
            // Screen recording permission changes typically require relaunch before
            // the running process sees a new effective access state.
            appActiveObserver = nil
            return
        }

        observeAppActiveIfNeeded()
    }

    private func observeAppActiveIfNeeded() {
        guard appActiveObserver == nil else { return }

        let observer = AppActiveObserver(
            manager: self,
            notificationCenter: appNotificationCenter
        )
        observer.startObserving()
        appActiveObserver = observer
    }
}
