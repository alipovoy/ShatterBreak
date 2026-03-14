import Foundation

@testable import ShatterBreak

final class TestEnvironment {
    let suiteName = "ShatterBreakTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()

    init() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite for tests.")
        }

        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func makeTimerState(
        overlayManager: any OverlayManaging,
        postponeDurationSecs: Double = 60
    ) -> TimerState {
        TimerState(
            overlayManager: overlayManager,
            postponeDurationSecs: postponeDurationSecs,
            defaults: defaults,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    @MainActor
    func makePermissionManager() -> ScreenCapturePermissionManager {
        ScreenCapturePermissionManager(
            defaults: defaults,
            appNotificationCenter: appNotificationCenter
        )
    }
}
