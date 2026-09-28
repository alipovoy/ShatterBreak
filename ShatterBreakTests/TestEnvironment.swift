import Foundation

@testable import ShatterBreak

@MainActor
final class TestEnvironment {
    /// A domain of its own, removed with the environment, so no test sees another's writes.
    let defaults: UserDefaults
    private let suiteName = "dev.lipovoy.shatterbreak.tests.\(UUID().uuidString)"
    let clock = TestClock()
    /// The timer ``advanceTime(by:ticks:)`` reconciles, as its own boundary timer would.
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

    func advanceUntil(by interval: TimeInterval = 1, maxTicks: Int = 5, condition: () -> Bool) async {
        for _ in 0..<maxTicks where condition() == false {
            await advanceTime(by: interval)
        }
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
