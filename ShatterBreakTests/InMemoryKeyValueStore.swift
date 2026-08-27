import Foundation

@testable import ShatterBreak

/// A volatile `KeyValueStore`: isolated per instance, never written to disk.
///
/// Replaces the per-test `UserDefaults(suiteName:)` suites, which left a backing `plist`
/// behind on every run.
///
/// Coercions mirror `UserDefaults` for the kinds this app stores: durations as `Double`,
/// flags as `Bool`, enum raw values as `String`.
final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    func object(forKey key: String) -> Any? {
        lock.withLock { storage[key] }
    }

    func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    func double(forKey key: String) -> Double {
        switch object(forKey: key) {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value) ?? 0
        default: return 0
        }
    }

    func bool(forKey key: String) -> Bool {
        switch object(forKey: key) {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as Int: return value != 0
        default: return false
        }
    }

    func set(_ value: Any?, forKey key: String) {
        lock.withLock {
            if let value {
                storage[key] = value
            } else {
                _ = storage.removeValue(forKey: key)
            }
        }
    }

    func removeObject(forKey key: String) {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }
}
