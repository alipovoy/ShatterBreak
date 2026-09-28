import Foundation
import Testing

@testable import ShatterBreak

@Suite("StatisticsStore", .tags(.statistics), .timeLimit(.minutes(1)))
@MainActor
struct StatisticsStoreTests {
    let environment = TestEnvironment()
    var defaults: any KeyValueStore { environment.defaults }
    @Test("recording increments counters and persists across store instances")
    func recordingPersistsAcrossInstances() {
        defaults.set(true, forKey: PreferenceKeys.trackStatistics)

        let store = StatisticsStore(defaults: defaults)
        store.record(.workSessionCompleted)
        store.record(.breakCompleted)
        store.record(.breakCompleted)
        store.record(.postponed)
        store.record(.earlyReturn)

        let reloaded = StatisticsStore(defaults: defaults)
        #expect(reloaded.current == store.current, "A relaunch should load the persisted tally unchanged.")
        #expect(reloaded.current.workSessionsCompleted == 1, "The work session count should persist.")
        #expect(reloaded.current.breaksCompleted == 2, "The break count should persist.")
        #expect(reloaded.current.postponesUsed == 1, "The postpone count should persist.")
        #expect(reloaded.current.earlyReturns == 1, "The early-return count should persist.")
    }

    @Test("record is a no-op while tracking is disabled")
    func recordIsNoOpWhileDisabled() {

        let store = StatisticsStore(defaults: defaults)
        store.record(.workSessionCompleted)

        #expect(store.current.workSessionsCompleted == 0, "Tracking is off by default, so nothing should count.")
        #expect(
            defaults.object(forKey: PreferenceKeys.sessionStatistics) == nil,
            "A disabled tracker should never write to the store."
        )
    }

    @Test("reset zeroes the counters and restamps since")
    func resetZeroesCountersAndRestampsSince() {
        defaults.set(true, forKey: PreferenceKeys.trackStatistics)

        let store = StatisticsStore(defaults: defaults)
        store.record(.workSessionCompleted)
        let before = Date.now
        store.reset()

        #expect(store.current.workSessionsCompleted == 0, "Reset should zero the counters.")
        #expect(store.current.since >= before, "Reset should stamp since with the present moment.")

        let reloaded = StatisticsStore(defaults: defaults)
        #expect(reloaded.current == store.current, "The reset tally should persist.")
    }

    @Test("automatic reset requires both tracking and the opt-in preference")
    func automaticResetRequiresBothPreferences() {
        defaults.set(true, forKey: PreferenceKeys.trackStatistics)

        let store = StatisticsStore(defaults: defaults)
        store.record(.workSessionCompleted)

        store.resetForNewSessionIfEnabled()
        #expect(store.current.workSessionsCompleted == 1, "Without the opt-in, a new session should not reset.")

        defaults.set(true, forKey: PreferenceKeys.resetStatisticsOnStart)
        defaults.set(false, forKey: PreferenceKeys.trackStatistics)
        store.resetForNewSessionIfEnabled()
        #expect(store.current.workSessionsCompleted == 1, "A disabled tracker should never mutate its values.")

        defaults.set(true, forKey: PreferenceKeys.trackStatistics)
        store.resetForNewSessionIfEnabled()
        #expect(store.current.workSessionsCompleted == 0, "With both preferences on, a new session resets.")
    }

    @Test("unreadable stored data falls back to a fresh zero tally")
    func unreadableDataFallsBackToFreshTally() {
        defaults.set(Data("not json".utf8), forKey: PreferenceKeys.sessionStatistics)

        let store = StatisticsStore(defaults: defaults)

        #expect(store.current == SessionStatistics(since: store.current.since), "Bad data should yield a fresh tally.")
    }
}
