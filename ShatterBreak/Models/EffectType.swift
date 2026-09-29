import Foundation

/// The break screen's look. The raw value is what is persisted, so renaming a case changes it.
enum EffectType: String, CaseIterable, Identifiable {
    /// A frozen, frosted, cracked screenshot. Falls back to ``fogged`` without capture consent.
    case shatter
    /// Cracked fog over the live desktop, needing no capture.
    case fogged
    case dimmed

    var id: String { rawValue }

    /// The one answer to "may this app raise a screen-capture dialog": a user on another
    /// effect is never asked for anything (issue #90).
    var requiresScreenCapture: Bool {
        self == .shatter
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .shatter:
            .effectShatter
        case .fogged:
            .effectFogged
        case .dimmed:
            .effectDimmed
        }
    }
}
