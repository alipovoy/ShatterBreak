import AppKit

/// The two consents Shatter needs: classic Screen Recording, which CoreGraphics can preflight
/// and request, and macOS's separate direct-capture consent, learned only by attempting one.
@MainActor
@Observable
final class ScreenCapturePermissionManager {
    static let shared = ScreenCapturePermissionManager()

    /// "Denied" and "never asked" are the same answer here: both block the capture, show the
    /// same warning and are fixed in the same place.
    private(set) var hasScreenRecordingAccess = false

    /// Independent of Screen Recording, which can be granted while this is refused (#90).
    private(set) var directCaptureAccess: DirectCaptureAccess = .unknown

    /// An ``DirectCaptureAccess/unknown`` answer does not block: the next session settles it.
    var isCaptureBlocked: Bool {
        hasScreenRecordingAccess == false || directCaptureAccess == .refused
    }

    /// Persisted, so a login-item app does not raise macOS's monthly ask at every boot.
    private static let directCaptureDeclinedKey = "com.shatterbreak.directCaptureDeclined"

    private var activationObserver: (any NSObjectProtocol)?
    private var confirmation: Task<Void, Never>?
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
        directCaptureAccess = defaults.bool(forKey: Self.directCaptureDeclinedKey) ? .refused : .unknown
        refresh()
    }

    isolated deinit {
        if let activationObserver {
            appNotificationCenter.removeObserver(activationObserver)
        }
    }

    func refresh() {
        hasScreenRecordingAccess = permissionClient.preflightAccess()
        // Once granted there is nothing left to watch for.
        if hasScreenRecordingAccess, let activationObserver {
            appNotificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        } else if hasScreenRecordingAccess == false, activationObserver == nil {
            activationObserver = appNotificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func openSystemSettings() {
        permissionClient.openSystemSettings()
    }

    /// Called as a work session begins: macOS raises its direct-capture dialog at the first
    /// capture request, and one made early keeps it out of the break. Screen Recording goes
    /// first, or the probe fails for the wrong reason.
    func prepareForCapture() async {
        refresh()
        requestAccessIfNeeded()

        guard isCaptureBlocked == false else { return }

        // Joined, not skipped: returning early would hand the caller an answer not yet in.
        if let confirmation {
            return await confirmation.value
        }

        let task = Task {
            let isAllowed = await permissionClient.confirmDirectCaptureAccess()
            directCaptureAccess = isAllowed ? .allowed : .refused
            defaults.set(isAllowed == false, forKey: Self.directCaptureDeclinedKey)
            confirmation = nil
        }
        confirmation = task
        await task.value
    }

    /// Re-opens the direct-capture dialog, clearing a remembered decline. System Settings has
    /// no switch for this consent.
    func confirmDirectCaptureAccess() async {
        directCaptureAccess = .unknown
        defaults.set(false, forKey: Self.directCaptureDeclinedKey)
        await prepareForCapture()
    }

    /// macOS prompts only while it holds no answer, so asking each launch is free and recovers
    /// a grant lost to re-signing (issue #43).
    func requestAccessIfNeeded() {
        guard hasScreenRecordingAccess == false, hasRequestedAccessThisLaunch == false else { return }
        hasRequestedAccessThisLaunch = true
        _ = permissionClient.requestAccess()
    }
}
