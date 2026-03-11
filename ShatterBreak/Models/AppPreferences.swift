import Foundation

/// Defines the types of visual effects available for the working state.
enum EffectType: String, CaseIterable, Identifiable {
    case shatter = "Shatter"
    case overlay = "Overlay"

    var id: String { self.rawValue }
}

/// Controls whether the work timer should start automatically when a break ends
/// or wait for the user to manually indicate they’ve returned.
enum WorkStartMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual = "Manual"

    var id: String { self.rawValue }
}
