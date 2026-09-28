import Foundation

extension UserDefaults {
    /// For previews reading `@AppStorage`, which sees nothing but `UserDefaults`; the rest use
    /// ``InMemoryKeyValueStore``.
    static func preview(_ name: String = "default") -> UserDefaults {
        UserDefaults(suiteName: "dev.lipovoy.shatterbreak.previews.\(name)") ?? .standard
    }
}
