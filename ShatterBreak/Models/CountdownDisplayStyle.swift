import Foundation

/// How a countdown renders, and so how often it must redraw. `minutes` ("24m") redraws once
/// a minute with a loose tolerance, and falls back to MM:SS for the final minute.
enum CountdownDisplayStyle: Equatable {
    case seconds
    case minutes

    static let finalCountdownThreshold: TimeInterval = 60

    /// Minutes round up, as MM:SS does: "24m" means no more than 24 minutes remain.
    func text(forRemaining remaining: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .seconds:
            return TimerState.format(timeInterval: remaining)
        case .minutes:
            guard remaining > Self.finalCountdownThreshold else {
                return TimerState.format(timeInterval: remaining)
            }
            let wholeMinutes = Int(ceil(remaining / 60))
            return Duration.seconds(wholeMinutes * 60)
                .formatted(.units(allowed: [.minutes], width: .narrow).locale(locale))
        }
    }

    /// Exactly the time until the text next changes.
    func nextRefreshDelay(forRemaining remaining: TimeInterval) -> Duration {
        switch self {
        case .seconds:
            return Self.delayToNextBoundary(forRemaining: remaining, boundary: 1)
        case .minutes:
            guard remaining > Self.finalCountdownThreshold else {
                return Self.delayToNextBoundary(forRemaining: remaining, boundary: 1)
            }
            return Self.delayToNextBoundary(forRemaining: remaining, boundary: 60)
        }
    }

    func refreshTolerance(forRemaining remaining: TimeInterval) -> Duration {
        switch self {
        case .seconds:
            return .milliseconds(100)
        case .minutes:
            return remaining > Self.finalCountdownThreshold ? .seconds(5) : .milliseconds(100)
        }
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
