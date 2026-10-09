import Foundation

/// How a countdown renders, and so how often it must redraw. `minutes` ("24m") redraws once
/// a minute with a loose tolerance, then counts whole seconds ("59s") below one minute.
enum CountdownDisplayStyle: Equatable {
    case seconds
    case minutes

    static let finalCountdownThreshold: TimeInterval = 60

    /// Whole minutes left, read off the MM:SS clock: 1:10 is "1m", and "59s" follows 1:00.
    func text(forRemaining remaining: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .seconds:
            return TimerState.format(timeInterval: remaining)
        case .minutes:
            let shown = Self.shownSeconds(forRemaining: remaining)
            return Duration.seconds(shown)
                .formatted(.units(allowed: [shown >= 60 ? .minutes : .seconds], width: .narrow).locale(locale))
        }
    }

    /// Exactly the time until the text next changes.
    func nextRefreshDelay(forRemaining remaining: TimeInterval) -> Duration {
        switch self {
        case .seconds:
            return Self.delayToNextBoundary(forRemaining: remaining, boundary: 1)
        case .minutes:
            // The text holds until the displayed seconds drop below the figure it shows.
            let lastSecondShown = Self.shownSeconds(forRemaining: remaining)
            return .seconds(max(remaining - Double(lastSecondShown - 1), 0))
        }
    }

    func refreshTolerance(forRemaining remaining: TimeInterval) -> Duration {
        switch self {
        case .seconds:
            return .milliseconds(100)
        case .minutes:
            // Judged where the sleep ends, so the one into the final minute cannot skip "59s".
            let remainingAtWake = remaining - nextRefreshDelay(forRemaining: remaining) / .seconds(1)
            return remainingAtWake > Self.finalCountdownThreshold ? .seconds(5) : .milliseconds(100)
        }
    }

    /// The seconds the minutes style stands for: whole minutes from a minute up, else the seconds.
    private static func shownSeconds(forRemaining remaining: TimeInterval) -> Int {
        let displayed = TimerState.displaySeconds(for: remaining)
        return displayed >= 60 ? displayed / 60 * 60 : displayed
    }

    private static func delayToNextBoundary(
        forRemaining remaining: TimeInterval,
        boundary: TimeInterval
    ) -> Duration {
        let toBoundary = remaining.truncatingRemainder(dividingBy: boundary)
        return .seconds(toBoundary > 0 ? toBoundary : boundary)
    }
}

extension CountdownDisplayStyle {
    /// Calls `onTick` now and at each moment the text can change, until the interval runs
    /// out or the task is cancelled. Moments come from the timer's clock, never `Date.now`.
    @MainActor
    func driveCountdown(for state: TimerState, onTick: (Date) -> Void) async {
        var referenceDate = state.now().date
        onTick(referenceDate)

        guard state.isRunning else { return }

        while Task.isCancelled == false {
            let remaining = state.timeRemaining(at: referenceDate)
            guard remaining > 0 else { return }

            do {
                try await Task.sleep(
                    for: nextRefreshDelay(forRemaining: remaining),
                    tolerance: refreshTolerance(forRemaining: remaining)
                )
            } catch {
                return
            }

            referenceDate = state.now().date
            onTick(referenceDate)
        }
    }
}
