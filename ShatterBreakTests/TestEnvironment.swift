import CoreGraphics
import Foundation

@testable import ShatterBreak

final class TestEnvironment {
    let defaults: any KeyValueStore = InMemoryKeyValueStore()
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    let defaultsNotificationCenter = NotificationCenter()
    private var cachedClock: ManualTimerClock?
    /// Lit unless a DarkWake-gating test says otherwise, so overlay assertions stay about
    /// the state machine.
    @MainActor
    var isDisplayAwake = true

    /// Empty unless a gating test sleeps one. Held here rather than in a captured local so
    /// a test can sleep or wake a display after the manager already holds the closure.
    @MainActor
    var asleepDisplays: Set<CGDirectDisplayID> = []

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
    /// - Parameter directCaptureAccess: `.unknown` by default, matching the app before its
    ///   probe answers. A test needing shatter to survive `resolveEffectType` passes
    ///   `.allowed`.
    func makeOverlayManager(
        captureClient: ScreenCaptureClient = .live,
        notificationCenter: NotificationCenter = NotificationCenter(),
        directCaptureAccess: @escaping @MainActor () -> DirectCaptureAccess = { .unknown }
    ) -> OverlayManager {
        OverlayManager(
            defaults: defaults,
            captureClient: captureClient,
            notificationCenter: notificationCenter,
            // Shared with the screen-parameter observer: tests post both display-reconfiguration
            // and sleep/wake notifications on the one center they hold a reference to.
            workspaceNotificationCenter: notificationCenter,
            directCaptureAccess: directCaptureAccess,
            isDisplayAwake: { [unowned self] in asleepDisplays.contains($0) == false }
        )
    }

    /// For tests planting a timestamp the timer will measure against.
    @MainActor
    var now: Date { clock.date }

    @MainActor
    func advanceTime(by interval: TimeInterval = 1, ticks: Int = 1) async {
        for _ in 0..<ticks {
            clock.advance(by: interval)
        }
    }

    /// Awake but not reconciling: a dropped boundary timer, not an absence.
    @MainActor
    func elapseTimeWithoutTick(by interval: TimeInterval) {
        clock.elapse(by: interval)
    }

    /// Asleep, with no notification to say so — the evidence an absence is measured from.
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
    func makeMenuBarController(state: TimerState) -> MenuBarController {
        MenuBarController(
            state: state,
            defaults: defaults,
            notificationCenter: defaultsNotificationCenter
        )
    }

    /// The preference is written by `@AppStorage`, not through the timer, so the posted
    /// notification is the only signal ``MenuBarController`` gets.
    @MainActor
    func setMenuBarTimerStyle(_ style: MenuBarTimerStyle) {
        defaults.set(style.rawValue, forKey: PreferenceKeys.menuBarTimerStyle)
        defaultsNotificationCenter.post(name: UserDefaults.didChangeNotification, object: nil)
    }

    /// Work posted to the main queue — a notification observer, a `Task` spawned from a
    /// main-actor object — lands a turn or more after the call that scheduled it, and a
    /// countdown's own sleep is a second long.
    @MainActor
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<600 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// For asserting that something did *not* happen, where there is no condition to poll.
    @MainActor
    func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
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
