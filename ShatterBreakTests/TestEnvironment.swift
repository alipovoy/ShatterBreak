import CoreGraphics
import Foundation

@testable import ShatterBreak

@MainActor
final class TestEnvironment {
    let defaults: any KeyValueStore = InMemoryKeyValueStore()
    let appNotificationCenter = NotificationCenter()
    let defaultsNotificationCenter = NotificationCenter()
    let clock = TestClock()
    /// The timer ``advanceTime(by:ticks:)`` reconciles, as its own boundary timer would.
    private weak var timer: TimerState?

    /// Asleep displays for overlay-manager tests. Held here rather than in a captured local
    /// so a test can sleep or wake a display after the manager already holds the closure.
    var asleepDisplays: Set<CGDirectDisplayID> = []

    func makeTimerState(overlays: (any BreakPresenting)? = nil) -> TimerState {
        let state = TimerState(defaults: defaults, overlays: overlays, now: { [clock] in clock.instant })
        timer = state
        return state
    }

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

    func advanceTime(by interval: TimeInterval = 1, ticks: Int = 1) async {
        for _ in 0..<ticks {
            clock.elapse(by: interval)
            timer?.reconcile()
        }
    }

    func advanceUntil(
        by interval: TimeInterval = 1,
        maxTicks: Int = 5,
        condition: () -> Bool
    ) async {
        for _ in 0..<maxTicks where condition() == false {
            await advanceTime(by: interval)
        }
    }

    func makeMenuBarController(state: TimerState) -> MenuBarController {
        MenuBarController(
            state: state,
            defaults: defaults,
            notificationCenter: defaultsNotificationCenter
        )
    }

    /// The preference is written by `@AppStorage`, not through the timer, so the posted
    /// notification is the only signal ``MenuBarController`` gets.
    func setMenuBarTimerStyle(_ style: MenuBarTimerStyle) {
        defaults.set(style.rawValue, forKey: PreferenceKeys.menuBarTimerStyle)
        defaultsNotificationCenter.post(name: UserDefaults.didChangeNotification, object: nil)
    }

    /// Work posted to the main queue — a notification observer, a `Task` spawned from a
    /// main-actor object — lands a turn or more after the call that scheduled it, and a
    /// countdown's own sleep is a second long.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<600 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// For asserting that something did *not* happen, where there is no condition to poll.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

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
