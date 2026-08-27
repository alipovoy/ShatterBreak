import Foundation

extension UserDefaults {
    /// A throwaway preference domain for previews.
    ///
    /// `@AppStorage` reads `UserDefaults` and nothing else, so a pane of toggles cannot use
    /// ``InMemoryKeyValueStore`` the way other previews do. A named suite gives the canvas
    /// somewhere to write that is not the user's settings; `name` keeps one preview's
    /// seeded values out of another's.
    static func preview(_ name: String = "default") -> UserDefaults {
        UserDefaults(suiteName: "dev.lipovoy.shatterbreak.previews.\(name)") ?? .standard
    }
}
