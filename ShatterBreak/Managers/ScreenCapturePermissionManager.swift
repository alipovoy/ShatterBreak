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

    /// Whether macOS is currently letting the app capture the screen directly, without
    /// the system window picker.
    ///
    /// Independent of ``status``: Screen Recording can be granted while this is refused,
    /// which is exactly the case that used to ambush the user mid-break (issue #90).
    private(set) var directCaptureAccess: DirectCaptureAccess = .unknown

    private static let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private var appActiveObserver: AppActiveObserver?
    private var isConfirmingDirectCapture = false
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

    /// Settles every consent the shatter effect needs, ahead of the break that will use
    /// them.
    ///
    /// Called when a work session begins rather than when the break starts. macOS raises
    /// its direct-capture dialog lazily, at the first real ScreenCaptureKit call, so the
    /// only way to keep that dialog out of the break is to make the call earlier — while
    /// the user is at the start of a work session and has just chosen to run the timer.
    ///
    /// A refusal is remembered for the rest of the launch so the monthly confirmation
    /// never degenerates into a per-session nag; the user re-opens it deliberately via
    /// ``confirmDirectCaptureAccess()``. Screen Recording is settled first, because
    /// without it the probe would fail for an unrelated reason and mislabel the result.
    func prepareForCapture() async {
        requestIfFirstLaunch()
        refresh()

        guard status == .granted,
              directCaptureAccess != .refused,
              isConfirmingDirectCapture == false
        else {
            return
        }

        isConfirmingDirectCapture = true
        let isAllowed = await permissionClient.confirmDirectCaptureAccess()
        isConfirmingDirectCapture = false
        directCaptureAccess = isAllowed ? .allowed : .refused
    }

    /// Re-opens the system's direct-capture dialog after a refusal, on the user's own
    /// initiative from Preferences.
    func confirmDirectCaptureAccess() async {
        directCaptureAccess = .unknown
        await prepareForCapture()
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
