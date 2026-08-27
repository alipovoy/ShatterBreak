import Testing

@testable import ShatterBreak

/// What a machine still unattended is allowed to record.
///
/// The rule is one line — a phase that began after the machine went dark was never worked
/// — but which route a cycle takes to reach it depends on the durations, so the cases are
/// worth stating separately (#113).
@Suite("Unattended tallies", .tags(.timerState, .sleepWake))
struct UnattendedTallyTests {
    @Test("a break longer than the work session does not tally cycles in an empty room")
    func unattendedCyclesRecordNothingWhenRestOutlastsWork() {
        // Rest longer than work is what makes this reachable: the work boundary falls due
        // before the away-reset threshold does, so every cycle crosses instead of resetting.
        var driver = ReducerDriver(prefs: .testing(work: 60, rest: 600))
        driver.act(.start)
        driver.act(.observedSleep)

        // Eight hours of dark display, heartbeats throughout, and no wake ever delivered.
        for _ in 0..<(8 * 3_600 / 30) {
            driver.drift(30)
            driver.reconcile()
        }

        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 0,
            "No one worked these sessions; the away-reset route records nothing and this must agree."
        )
        #expect(driver.count(of: .record(.breakCompleted)) == 0, "Nor did anyone take these breaks.")
    }

    @Test("the session interrupted by an absence is still the user's, and still counts")
    func theCrossingThatEndsAnAttendedSessionIsRecorded() {
        var driver = ReducerDriver(prefs: .testing(work: 60, rest: 600))
        driver.act(.start)
        // Worked for fifty seconds, then the display went dark.
        driver.drift(50)
        driver.act(.observedSleep)
        driver.drift(10)
        driver.reconcile()

        #expect(driver.phase == .rest, "The work countdown ran out and the break began.")
        #expect(
            driver.count(of: .record(.workSessionCompleted)) == 1,
            "Suppressing empty-room tallies must not swallow the session that earned this break."
        )
    }
}
