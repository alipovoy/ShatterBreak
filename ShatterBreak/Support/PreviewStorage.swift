import Foundation

extension UserDefaults {
    /// A preference domain of its own for a preview, so the canvas never writes the user's
    /// settings and one preview's seeded values stay out of another's.
    static func preview(_ name: String = "default") -> UserDefaults {
        UserDefaults(suiteName: "dev.lipovoy.shatterbreak.previews.\(name)") ?? .standard
    }
}
