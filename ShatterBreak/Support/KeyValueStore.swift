import Foundation

/// A key-value persistence seam, satisfied by `UserDefaults` in the app and by an in-memory
/// store in tests, so that tests never touch the real preferences system.
///
/// `@AppStorage` requires a concrete `UserDefaults` and is not exercised by tests. The
/// surface mirrors `UserDefaults` exactly, so conformance is free.
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
    /// A duration preference, or `defaultValue` when unset.
    ///
    /// `double(forKey:)` cannot tell "unset" from "zero", and no duration the app stores is
    /// legitimately zero, so a non-positive reading means nothing was written.
    func duration(forKey key: String, default defaultValue: Double) -> Double {
        let stored = double(forKey: key)
        return stored > 0 ? stored : defaultValue
    }
}
