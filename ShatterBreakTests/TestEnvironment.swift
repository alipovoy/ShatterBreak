import Foundation

@testable import ShatterBreak

final class TestEnvironment {
    let suiteName = "ShatterBreakTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    private var cachedScheduler: ManualCountdownScheduler?

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
    private var scheduler: ManualCountdownScheduler {
        if let cachedScheduler {
            return cachedScheduler
        }

        let scheduler = ManualCountdownScheduler()
        cachedScheduler = scheduler
        return scheduler
    }

    @MainActor
    func makeTimerState(
        overlays: OverlayPresenter = .disabled,
        postponeDurationSecs: Double = 60
    ) -> TimerState {
        TimerState(
            overlays: overlays,
            postponeDurationSecs: postponeDurationSecs,
            defaults: defaults,
            scheduler: scheduler,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
    }

    @MainActor
    func makeOverlayManager(
        captureClient: ScreenCaptureClient = .live
    ) -> OverlayManager {
        OverlayManager(defaults: defaults, captureClient: captureClient)
    }

    @MainActor
    func advanceTime(by interval: TimeInterval = 1, ticks: Int = 1) async {
        for _ in 0..<ticks {
            scheduler.advance(by: interval)
        }
    }

    @MainActor
    func elapseTimeWithoutTick(by interval: TimeInterval) {
        scheduler.elapse(by: interval)
    }

    @MainActor
    func advanceUntil(
        by interval: TimeInterval = 1,
        maxTicks: Int = 5,
        condition: () -> Bool
    ) async {
        for _ in 0..<maxTicks where condition() == false {
            await advanceTime(by: interval)
        }
    }

    @MainActor
    func makePermissionManager(
        permissionClient: ScreenCapturePermissionClient = .live
    ) -> ScreenCapturePermissionManager {
        ScreenCapturePermissionManager(
            defaults: defaults,
            appNotificationCenter: appNotificationCenter,
            permissionClient: permissionClient
        )
    }
}
