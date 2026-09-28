import Foundation

/// `UserDefaults` in the app, ``InMemoryKeyValueStore`` in tests: a `UserDefaults` suite
/// leaves its file behind in the sandbox container on every run.
protocol KeyValueStore: Sendable {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

extension KeyValueStore {
    /// `double(forKey:)` cannot tell unset from zero, and no duration the app stores is
    /// legitimately zero, so a non-positive reading means nothing was written.
    func duration(forKey key: String, default defaultValue: Double) -> Double {
        let stored = double(forKey: key)
        return stored > 0 ? stored : defaultValue
    }

    /// An unrecognized stored string falls back rather than being trusted.
    func value<V: RawRepresentable>(forKey key: String, default defaultValue: V) -> V
    where V.RawValue == String {
        string(forKey: key).flatMap(V.init(rawValue:)) ?? defaultValue
    }
}
