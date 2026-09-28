import Foundation

extension UserDefaults {
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
