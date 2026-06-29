import Foundation

/// Defines the types of visual effects available for the working state.
///
/// The lowercase `rawValue` of each case is the string persisted in user defaults,
/// so renaming a case changes the stored key. Any unrecognized stored value decodes
/// to `nil`, letting the read sites fall back to a default rather than trusting a
/// corrupt preference.
enum EffectType: String, CaseIterable, Identifiable {
    /// A captured screenshot frozen, frosted, and fractured with cracks. Requires
    /// Screen Recording permission; falls back to ``fogged`` when it is missing.
    case shatter
    /// Fogged glass over the live desktop with cracks, but no screenshot capture
    /// or shatter animation. Doubles as the permission-less ``shatter`` fallback.
    case fogged
    /// A simple dimmed overlay over the desktop, with no cracks or shatter.
    case dimmed

    var id: String { rawValue }

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
