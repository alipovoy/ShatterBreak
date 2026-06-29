import Foundation

@testable import ShatterBreak

final class TestEnvironment {
    let defaults: any KeyValueStore = InMemoryKeyValueStore()
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    private var cachedScheduler: ManualCountdownScheduler?

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
        postponeDurationSecs: Double? = nil
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
        captureClient: ScreenCaptureClient = .live,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> OverlayManager {
        OverlayManager(
            defaults: defaults,
            captureClient: captureClient,
            notificationCenter: notificationCenter
        )
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
