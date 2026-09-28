import CoreGraphics
import Foundation

@testable import ShatterBreak

@MainActor
final class TestEnvironment {
    /// A domain of its own, removed with the environment, so no test sees another's writes.
    let defaults: UserDefaults
    private let suiteName = "dev.lipovoy.shatterbreak.tests.\(UUID().uuidString)"
    let clock = TestClock()
    var asleepDisplays: Set<CGDirectDisplayID> = []
    private weak var timer: TimerState?

    init() {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeTimerState(overlays: (any BreakPresenting)? = nil) -> TimerState {
        let state = TimerState(defaults: defaults, overlays: overlays, now: { [clock] in clock.instant })
        timer = state
        return state
    }

    func advanceTime(by interval: TimeInterval = 1, ticks: Int = 1) async {
        for _ in 0..<ticks {
            clock.elapse(by: interval)
            timer?.reconcile()
        }
    }

    /// Awake with nothing reconciling: a lost boundary timer, not an absence.
    func elapseTimeWithoutTick(by interval: TimeInterval) {
        clock.elapse(by: interval)
    }

    /// Asleep, with no notification to say so.
    func sleepMachine(by interval: TimeInterval) {
        clock.sleepMachine(by: interval)
    }

    var now: Date { clock.date }

    func advanceUntil(by interval: TimeInterval = 1, maxTicks: Int = 5, condition: () -> Bool) async {
        for _ in 0..<maxTicks where condition() == false {
            await advanceTime(by: interval)
        }
    }

    /// Displays in `asleepDisplays` read as dark. Without `capture`, Screen Recording reads as
    /// missing, so shatter resolves to fogged and nothing is captured.
    func makeOverlayManager(
        screens: StubScreens? = nil,
        capture image: CGImage? = nil,
        directCaptureAccess: @escaping @MainActor () -> DirectCaptureAccess = { .unknown }
    ) -> OverlayManager {
        OverlayManager(
            defaults: defaults,
            screens: { screens?.screens ?? [] },
            capture: { displayIDs in
                guard let image else { return [:] }
                return Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, image) })
            },
            isDisplayAwake: { [unowned self] in asleepDisplays.contains($0) == false },
            hasScreenRecordingPermission: { image != nil },
            directCaptureAccess: directCaptureAccess
        )
    }

    let appNotificationCenter = NotificationCenter()

    func makePermissionManager(
        permissionClient: ScreenCapturePermissionClient = .live
    ) -> ScreenCapturePermissionManager {
        ScreenCapturePermissionManager(
            defaults: defaults,
            appNotificationCenter: appNotificationCenter,
            permissionClient: permissionClient
        )
    }

    /// `@AppStorage` writes the style, so the change notification is all the item hears.
    func setMenuBarTimerStyle(_ style: MenuBarTimerStyle) {
        defaults.set(style.rawValue, forKey: PreferenceKeys.menuBarTimerStyle)
    }

    /// Work posted to the main queue lands a turn or more after the call that scheduled it.
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
}
