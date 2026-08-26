import Foundation

@testable import ShatterBreak

final class TestEnvironment {
    let defaults: any KeyValueStore = InMemoryKeyValueStore()
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    private var cachedClock: ManualTimerClock?
    /// Whether the stub display is lit. Tests that care about DarkWake gating switch it
    /// off; everything else runs with a screen, so overlay assertions stay about the state
    /// machine rather than about display state.
    @MainActor
    var isDisplayAwake = true

    @MainActor
    var clock: ManualTimerClock {
        if let cachedClock {
            return cachedClock
        }

        let clock = ManualTimerClock()
        cachedClock = clock
        return clock
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
            clock: clock,
            workspaceNotificationCenter: workspaceNotificationCenter,
            isDisplayAwake: { [unowned self] in isDisplayAwake }
        )
    }

    @MainActor
    /// - Parameter directCaptureAccess: left `.unknown` by default, matching the app
    ///   before its probe answers. A test that needs the shatter effect to survive
    ///   ``OverlayManager/resolveEffectType(selected:hasScreenRecordingPermission:directCaptureAccess:)``
    ///   must pass `.allowed`.
    func makeOverlayManager(
        captureClient: ScreenCaptureClient = .live,
        notificationCenter: NotificationCenter = NotificationCenter(),
        directCaptureAccess: @escaping @MainActor () -> DirectCaptureAccess = { .unknown }
    ) -> OverlayManager {
        OverlayManager(
            defaults: defaults,
            captureClient: captureClient,
            notificationCenter: notificationCenter,
            directCaptureAccess: directCaptureAccess
        )
    }

    /// The clock's current moment, for tests that need to plant a timestamp the timer
    /// will measure against.
    @MainActor
    var now: Date { clock.date }

    @MainActor
    func advanceTime(by interval: TimeInterval = 1, ticks: Int = 1) async {
        for _ in 0..<ticks {
            clock.advance(by: interval)
        }
    }

    /// Time passing with the machine awake but nothing reconciling — a dropped boundary
    /// timer, not an absence.
    @MainActor
    func elapseTimeWithoutTick(by interval: TimeInterval) {
        clock.elapse(by: interval)
    }

    /// Time passing with the machine asleep, and no notification to say so. The wall clock
    /// moves while the awake-only clock does not, which is the evidence an absence is
    /// measured from.
    @MainActor
    func sleepMachine(by interval: TimeInterval) {
        clock.sleepMachine(by: interval)
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
