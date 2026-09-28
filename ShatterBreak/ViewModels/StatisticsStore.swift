import Foundation

enum StatisticsEvent: Equatable {
    case workSessionCompleted
    case breakCompleted
    case postponed
    case earlyReturn
}

/// Disabling tracking stops counting but keeps the values; a relaunch keeps them too.
@MainActor
@Observable
final class StatisticsStore {
    private(set) var current: SessionStatistics

    private let defaults: any KeyValueStore

    var isTrackingEnabled: Bool {
        (defaults.object(forKey: PreferenceKeys.trackStatistics) as? Bool)
            ?? PreferenceDefaults.trackStatistics
    }

    init(defaults: any KeyValueStore = UserDefaults.standard) {
        self.defaults = defaults
        self.current = Self.load(from: defaults) ?? SessionStatistics(since: .now)
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

    func reset() {
        current = SessionStatistics(since: .now)
        persist()
    }

    /// The opt-in reset at the stop→start boundary. A disabled tracker never changes.
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
