import Foundation

/// A minimal key-value persistence seam, satisfied by `UserDefaults` in the app
/// and by an in-memory store in tests.
///
/// Production code depends on this protocol rather than `UserDefaults` directly so
/// that unit tests never touch the real preferences system — no per-test suites,
/// no leaked `plist` files, and no dependency on the host app's sandbox container.
/// SwiftUI `@AppStorage` bindings (which require a concrete `UserDefaults`) are not
/// exercised by tests and continue to use `.standard`.
///
/// The surface mirrors `UserDefaults` exactly, so conformance is free.
protocol KeyValueStore: Sendable {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}
