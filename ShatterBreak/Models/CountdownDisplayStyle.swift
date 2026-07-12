import Foundation

/// How a live countdown renders its remaining time, and — because the refresh
/// cadence must match what the text can actually show — how long the display
/// stays valid before it needs another redraw.
///
/// `minutes` is the power-save style: the text carries only minute precision
/// (e.g. "24m"), so a single refresh per minute keeps it accurate, and a
/// generous timer tolerance lets the system coalesce the wake-ups. In the
/// final minute it hands over to the per-second MM:SS style so the countdown
/// stays legible where it matters.
enum CountdownDisplayStyle: Equatable {
    case seconds
    case minutes

    /// Remaining time at or below which `minutes` falls back to per-second MM:SS.
    static let finalCountdownThreshold: TimeInterval = 60

    /// The text for `remaining` seconds left on the clock.
    ///
    /// Minute counts round up, matching the ceiling the MM:SS formatter applies:
    /// "24m" means "no more than 24 minutes remain", and the value ticks over
    /// exactly when `remaining` crosses a multiple of 60.
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

    /// How long the text for `remaining` stays correct — the sleep until the
    /// next redraw. Always the exact distance to the next value change, so the
    /// display is never stale regardless of cadence.
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

    /// The slack the next refresh can absorb. Minute-level sleeps accept several
    /// seconds so the system can coalesce timers (the energy win this style
    /// exists for); per-second ticks stay tight to keep the countdown smooth.
    func refreshTolerance(forRemaining remaining: TimeInterval) -> Duration {
        switch self {
        case .seconds:
            return .milliseconds(100)
        case .minutes:
            return remaining > Self.finalCountdownThreshold ? .seconds(5) : .milliseconds(100)
        }
    }

    /// The time until `remaining` next crosses a multiple of `boundary`, or a
    /// full `boundary` when it sits exactly on one.
    private static func delayToNextBoundary(
        forRemaining remaining: TimeInterval,
        boundary: TimeInterval
    ) -> Duration {
        let toBoundary = remaining.truncatingRemainder(dividingBy: boundary)
        return .seconds(toBoundary > 0 ? toBoundary : boundary)
    }
}
