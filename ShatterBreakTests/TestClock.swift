import Foundation

@testable import ShatterBreak

/// Time moved by hand. The two ways it can pass are kept apart, because the timer tells
/// them apart: awake, both clocks move; asleep, only the wall clock does.
@MainActor
final class TestClock {
    private(set) var date = Date(timeIntervalSince1970: 0)
    private(set) var awakeUptime: TimeInterval = 10_000

    var instant: TimerInstant { TimerInstant(date: date, awakeUptime: awakeUptime) }

    func elapse(by interval: TimeInterval) {
        date += interval
        awakeUptime += interval
    }

    func sleepMachine(by interval: TimeInterval) {
        date += interval
    }
}

/// Stands in for the screen: records what the timer put on it.
@MainActor
final class PresenterSpy: BreakPresenting {
    var hasAwakeScreen = true
    private(set) var presentedState: TimerState?
    private(set) var shown: [OverlayPresentationStyle] = []
    private(set) var dismissCount = 0
    private(set) var prepareCount = 0

    func prepareCapture() async {
        prepareCount += 1
    }

    func show(_ state: TimerState, style: OverlayPresentationStyle) {
        shown.append(style)
        presentedState = state
    }

    func dismiss() {
        dismissCount += 1
        presentedState = nil
    }
}
