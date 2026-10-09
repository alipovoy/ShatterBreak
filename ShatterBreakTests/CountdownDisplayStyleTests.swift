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

    @Test("Seconds style keeps minutes above 99 whole")
    func secondsStyleDoesNotTruncateLongSessions() {
        #expect(CountdownDisplayStyle.seconds.text(forRemaining: 6000, locale: english) == "100:00")
        #expect(CountdownDisplayStyle.seconds.text(forRemaining: 6900, locale: english) == "115:00")
        #expect(CountdownDisplayStyle.seconds.text(forRemaining: 7200, locale: english) == "120:00")
    }

    @Test("Minutes style shows the whole minutes left, as the MM:SS clock would")
    func minutesStyleShowsWholeMinutes() {
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1500, locale: english) == "25m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1441, locale: english) == "24m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1440, locale: english) == "24m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 70, locale: english) == "1m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 61, locale: english) == "1m")
    }

    @Test("Minutes style counts whole seconds below one minute, without switching format")
    func minutesStyleShowsSecondsInFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 60, locale: english) == "1m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 59.5, locale: english) == "1m")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 59, locale: english) == "59s")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 12.3, locale: english) == "13s")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 1, locale: english) == "1s")
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: 0, locale: english) == "0s")
    }

    @Test("Seconds style sleeps to the next second boundary")
    func secondsStyleSleepsToNextSecond() {
        #expect(CountdownDisplayStyle.seconds.nextRefreshDelay(forRemaining: 90) == .seconds(1))
        #expect(CountdownDisplayStyle.seconds.nextRefreshDelay(forRemaining: 90.25) == .seconds(0.25))
    }

    @Test("Minutes style sleeps until the text drops a minute")
    func minutesStyleSleepsToNextMinute() {
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1500) == .seconds(1))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1499) == .seconds(60))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1498.5) == .seconds(59.5))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 61) == .seconds(2))
    }

    @Test("Minutes style ticks per second within the final minute")
    func minutesStyleTicksPerSecondInFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 59.5) == .seconds(0.5))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 60) == .seconds(1))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 42.5) == .seconds(0.5))
    }

    @Test("Minutes style relaxes tolerance only for sleeps that end above the final minute")
    func minutesStyleRelaxesToleranceAboveFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 1500) == .seconds(5))
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 120) == .seconds(5))
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 119) == .milliseconds(100))
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 61) == .milliseconds(100))
        #expect(CountdownDisplayStyle.minutes.refreshTolerance(forRemaining: 60) == .milliseconds(100))
        #expect(CountdownDisplayStyle.seconds.refreshTolerance(forRemaining: 1500) == .milliseconds(100))
    }

    @Test("Minutes style never shows a negative time")
    func minutesStyleClampsNegativeRemaining() {
        #expect(CountdownDisplayStyle.minutes.text(forRemaining: -5, locale: english) == "0s")
    }

    @Test("Minutes style wakes exactly when the text changes, down to the last second")
    func minutesStyleDelayLandsOnTextChange() {
        let style = CountdownDisplayStyle.minutes
        for tenths in 1...1900 {
            let remaining = Double(tenths) / 10
            let delay = style.nextRefreshDelay(forRemaining: remaining)
            let seconds = Double(delay.components.seconds) + Double(delay.components.attoseconds) / 1e18
            let before = style.text(forRemaining: remaining - seconds + 0.001, locale: english)
            let after = style.text(forRemaining: remaining - seconds - 0.001, locale: english)
            #expect(before == style.text(forRemaining: remaining, locale: english))
            #expect(after != before)
        }
    }

    @Test("Minutes style lands on the second boundaries around the final minute")
    func minutesStyleDelayAroundFinalMinute() {
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 60.5) == .seconds(1.5))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 119.5) == .seconds(0.5))
        #expect(CountdownDisplayStyle.minutes.nextRefreshDelay(forRemaining: 1) == .seconds(1))
    }
}
