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

    /// Whether Screen Recording has ever been requested. Named for the old "has launched
    /// before" behaviour it replaces — the two were always set at the same moment, so the
    /// stored value already means what it now says and needs no migration.
    private static let hasRequestedAccessKey = "com.shatterbreak.hasLaunchedBefore"

    /// A remembered decline of macOS's direct-capture confirmation. Persisted so the
    /// monthly ask does not reappear on every launch of a login-item menu bar app; the
    /// user re-opens it deliberately (issue #90).
    private static let directCaptureDeclinedKey = "com.shatterbreak.directCaptureDeclined"

    private var appActiveObserver: AppActiveObserver?
    private var isConfirmingDirectCapture = false
    private var hasRequestedAccessThisLaunch = false
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
        self.directCaptureAccess = defaults.bool(forKey: Self.directCaptureDeclinedKey)
            ? .refused
            : .unknown
        refresh()
    }

    func refresh() {
        if permissionClient.preflightAccess() {
            status = .granted
        } else {
            status = hasRequestedAccess ? .denied : .notDetermined
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
    /// A refusal is remembered *across* launches, because this app lives in the menu bar
    /// and typically starts at login: re-probing each launch would put the system dialog
    /// on screen at every boot, far more often than the monthly cadence macOS itself
    /// considers reasonable. The user re-opens it deliberately instead — see
    /// ``confirmDirectCaptureAccess()``. Screen Recording is settled first, because
    /// without it the probe would fail for an unrelated reason and mislabel the result.
    func prepareForCapture() async {
        refresh()
        requestAccessIfNeeded()

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
        defaults.set(isAllowed == false, forKey: Self.directCaptureDeclinedKey)
    }

    /// Re-opens the system's direct-capture dialog, clearing a remembered decline.
    ///
    /// The only two ways back: this, from the Preferences warning, and re-selecting the
    /// Shatter effect. Both are explicit statements that the user does want the frozen
    /// screen, which is what a remembered decline is waiting for.
    func confirmDirectCaptureAccess() async {
        directCaptureAccess = .unknown
        defaults.set(false, forKey: Self.directCaptureDeclinedKey)
        await prepareForCapture()
    }

    /// Requests Screen Recording when it is absent, at most once per launch.
    ///
    /// macOS decides whether a dialog actually appears: `CGRequestScreenCaptureAccess()`
    /// prompts only "if absent", and returns silently once TCC holds an answer. Asking
    /// on each launch therefore costs nothing — and is what makes the app recover on its
    /// own, because the grant is keyed to the code-signing identity, so an ad-hoc rebuild
    /// (issue #43) leaves TCC with no record and the app needing to ask again. Gating
    /// this on a persisted "has launched before" flag meant it never did.
    ///
    /// The per-launch cap is belt-and-braces against a macOS that re-prompts after a
    /// denial; the persisted flag now only separates ``Status/notDetermined`` from
    /// ``Status/denied`` for the UI.
    func requestAccessIfNeeded() {
        guard status != .granted, hasRequestedAccessThisLaunch == false else { return }

        hasRequestedAccessThisLaunch = true
        defaults.set(true, forKey: Self.hasRequestedAccessKey)
        updateAppActiveObservation()
        _ = permissionClient.requestAccess()
    }

    private var hasRequestedAccess: Bool {
        defaults.bool(forKey: Self.hasRequestedAccessKey)
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
