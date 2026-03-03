import Foundation

/// Defines the types of visual effects available for the working state.
enum EffectType: String, CaseIterable, Identifiable {
    case shatter = "Shatter"
    case overlay = "Overlay"

    var id: String { self.rawValue }
}
