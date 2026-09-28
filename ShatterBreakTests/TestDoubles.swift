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
final class OverlayRecorder: BreakPresenting {
    var hasAwakeScreen = true
    private(set) var presentedState: TimerState?
    private(set) var prepareCount = 0
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    private(set) var lastSettled: Bool?
    /// The timer the last `show` was given, which may since have been dismissed.
    private(set) var lastState: TimerState?

    private var prepareGate: CheckedContinuation<Void, Never>?
    private var holdsPrepare = false

    func holdPrepare() { holdsPrepare = true }

    func releasePrepare() {
        holdsPrepare = false
        prepareGate?.resume()
        prepareGate = nil
    }

    /// Waits for preparations the timer starts and does not await; bounded, so a regression
    /// reports the count it reached instead of hanging.
    func prepared(_ count: Int) async {
        for _ in 0..<100 where prepareCount < count {
            await Task.yield()
        }
    }

    func prepareCapture() async {
        prepareCount += 1
        guard holdsPrepare else { return }
        await withCheckedContinuation { prepareGate = $0 }
    }

    func show(_ state: TimerState, style: OverlayPresentationStyle) {
        showCount += 1
        lastSettled = style == .settled
        lastState = state
        presentedState = state
    }

    func dismiss() {
        dismissCount += 1
        presentedState = nil
    }
}
