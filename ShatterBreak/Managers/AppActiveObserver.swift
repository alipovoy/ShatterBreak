import AppKit

@MainActor
final class AppActiveObserver: NSObject {
    private weak var manager: ScreenCapturePermissionManager?
    private let notificationCenter: NotificationCenter
    private var isObserving = false

    init(
        manager: ScreenCapturePermissionManager,
        notificationCenter: NotificationCenter
    ) {
        self.manager = manager
        self.notificationCenter = notificationCenter
    }

    func startObserving() {
        guard isObserving == false else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        isObserving = true
    }

    @objc private func handleAppDidBecomeActive() {
        manager?.refresh()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
