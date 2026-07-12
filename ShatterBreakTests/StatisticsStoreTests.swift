import Foundation
import Testing

@testable import ShatterBreak

@Suite("StatisticsStore", .tags(.statistics), .timeLimit(.minutes(1)))
struct StatisticsStoreTests {
    @Test("recording increments counters and persists across store instances")
    @MainActor
    func recordingPersistsAcrossInstances() {
        let defaults = InMemoryKeyValueStore()
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
    @MainActor
    func recordIsNoOpWhileDisabled() {
        let defaults = InMemoryKeyValueStore()

        let store = StatisticsStore(defaults: defaults)
        store.record(.workSessionCompleted)

        #expect(store.current.workSessionsCompleted == 0, "Tracking is off by default, so nothing should count.")
        #expect(
            defaults.object(forKey: PreferenceKeys.sessionStatistics) == nil,
            "A disabled tracker should never write to the store."
        )
    }

    @Test("reset zeroes the counters and restamps since")
    @MainActor
    func resetZeroesCountersAndRestampsSince() {
        let defaults = InMemoryKeyValueStore()
        defaults.set(true, forKey: PreferenceKeys.trackStatistics)

        var currentTime = Date(timeIntervalSinceReferenceDate: 1_000)
        let store = StatisticsStore(defaults: defaults, now: { currentTime })
        store.record(.workSessionCompleted)

        currentTime = Date(timeIntervalSinceReferenceDate: 2_000)
        store.reset()

        #expect(store.current.workSessionsCompleted == 0, "Reset should zero the counters.")
        #expect(store.current.since == currentTime, "Reset should stamp since with the present moment.")

        let reloaded = StatisticsStore(defaults: defaults)
        #expect(reloaded.current == store.current, "The reset tally should persist.")
    }

    @Test("automatic reset requires both tracking and the opt-in preference")
    @MainActor
    func automaticResetRequiresBothPreferences() {
        let defaults = InMemoryKeyValueStore()
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
    @MainActor
    func unreadableDataFallsBackToFreshTally() {
        let defaults = InMemoryKeyValueStore()
        defaults.set(Data("not json".utf8), forKey: PreferenceKeys.sessionStatistics)

        let fallbackTime = Date(timeIntervalSinceReferenceDate: 3_000)
        let store = StatisticsStore(defaults: defaults, now: { fallbackTime })

        #expect(store.current == SessionStatistics(since: fallbackTime), "Bad data should yield a fresh tally.")
    }
}
