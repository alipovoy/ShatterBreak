import Foundation
import Testing

@testable import ShatterBreak

/// Pins the contract between what `CountdownDisplayStyle` renders and how long
/// that rendering stays valid: the refresh delay must always land exactly on
/// the next moment the text would change, so a coarse cadence never shows a
/// stale value.
@Suite("Countdown display style", .timeLimit(.minutes(1)))
struct CountdownDisplayStyleTests {
    private let english = Locale(identifier: "en_US")

    // MARK: - Text

    @Test("Seconds style renders MM:SS at any remaining time")
    func secondsStyleRendersMinutesAndSeconds() {
        #expect(CountdownDisplayStyle.seconds.text(forRemaining: 1500, locale: english) == "25:00")
        #expect(CountdownDisplayStyle.seconds.text(forRemaining: 59.4, locale: english) == "01:00")
    }

    @Test("Minutes style rounds whole minutes up, matching the MM:SS ceiling")
    func minutesStyleRoundsUp() {
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1500, locale: english) == "25m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1441, locale: english) == "25m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1440, locale: english) == "24m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 61, locale: english) == "2m")
    }

    @Test("Minutes style hands over to MM:SS for the final minute")
    func minutesStyleShowsSecondsInFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 60, locale: english) == "01:00")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 12.3, locale: english) == "00:13")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 0, locale: english) == "00:00")
    }

    // MARK: - Refresh cadence

    @Test("Seconds style sleeps to the next second boundary")
    func secondsStyleSleepsToNextSecond() {
        #expect(CountdownDisplayStyle.seconds.nextRefreshDelay(forRemaining: 90) == .seconds(1))
        #expect(CountdownDisplayStyle.seconds.nextRefreshDelay(forRemaining: 90.25) == .seconds(0.25))
    }

    @Test("Minutes style sleeps to the next minute boundary")
    func minutesStyleSleepsToNextMinute() {
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1500) == .seconds(60))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1499.5) == .seconds(59.5))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 61) == .seconds(1))
    }

    @Test("Minutes style ticks per second within the final minute")
    func minutesStyleTicksPerSecondInFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 60) == .seconds(1))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 42.5) == .seconds(0.5))
    }

    @Test("Minutes style relaxes tolerance only for minute-level sleeps")
    func minutesStyleRelaxesToleranceAboveFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 1500) == .seconds(5))
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 60) == .milliseconds(100))
        #expect(CountdownDisplayStyle.seconds.refreshTolerance(forRemaining: 1500) == .milliseconds(100))
    }
}
