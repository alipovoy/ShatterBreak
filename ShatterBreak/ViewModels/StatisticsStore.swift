import Foundation

/// A countable moment in the work/rest cycle, recorded by ``TimerState`` at its
/// transition points and tallied by ``StatisticsStore``.
enum StatisticsEvent {
    case workSessionCompleted
    case breakCompleted
    case postponed
    case earlyReturn
}

/// Owns the session-statistics tally (issue #10).
///
/// Counting is gated on the "Track statistics" preference, read live so toggling it in
/// Preferences applies mid-session; disabling stops the counting but keeps the stored
/// values. The tally persists across relaunches — a relaunch by itself never resets
/// anything, so a mid-day reboot keeps the day's numbers.
@MainActor
@Observable
final class StatisticsStore {
    private(set) var current: SessionStatistics

    private let defaults: any KeyValueStore
    private let now: () -> Date

    var isTrackingEnabled: Bool {
        (defaults.object(forKey: PreferenceKeys.trackStatistics) as? Bool)
            ?? PreferenceDefaults.trackStatistics
    }

    init(defaults: any KeyValueStore = UserDefaults.standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.current = Self.load(from: defaults) ?? SessionStatistics(since: now())
    }

    func record(_ event: StatisticsEvent) {
        guard isTrackingEnabled else { return }

        switch event {
        case .workSessionCompleted:
            current.workSessionsCompleted += 1
        case .breakCompleted:
            current.breaksCompleted += 1
        case .postponed:
            current.postponesUsed += 1
        case .earlyReturn:
            current.earlyReturns += 1
        }
        persist()
    }

    /// Starts a fresh tally from zero, stamping `since` with the present moment.
    func reset() {
        current = SessionStatistics(since: now())
        persist()
    }

    /// The automatic reset at the stop→start boundary, when the user opted in.
    /// A disabled tracker never mutates its stored values, so both preferences gate it.
    func resetForNewSessionIfEnabled() {
        let resetOnStart = (defaults.object(forKey: PreferenceKeys.resetStatisticsOnStart) as? Bool)
            ?? PreferenceDefaults.resetStatisticsOnStart
        guard isTrackingEnabled, resetOnStart else { return }

        reset()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(current), forKey: PreferenceKeys.sessionStatistics)
    }

    private static func load(from defaults: any KeyValueStore) -> SessionStatistics? {
        guard let data = defaults.object(forKey: PreferenceKeys.sessionStatistics) as? Data else { return nil }
        return try? JSONDecoder().decode(SessionStatistics.self, from: data)
    }
}
