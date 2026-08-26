import Foundation

extension UserDefaults {
    /// A throwaway preference domain for previews.
    ///
    /// Previews reach for real storage more often than it looks: `@AppStorage` reads
    /// `UserDefaults` and nothing else, so a pane full of toggles cannot use
    /// ``InMemoryKeyValueStore`` the way the rest of the previews do. A named suite is the
    /// next best thing — the canvas gets somewhere to write that is not the user's
    /// settings. Pass a `name` to keep one preview's seeded values out of another's.
    static func preview(_ name: String = "default") -> UserDefaults {
        UserDefaults(suiteName: "dev.lipovoy.shatterbreak.previews.\(name)") ?? .standard
    }
}
