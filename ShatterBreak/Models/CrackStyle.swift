import Foundation

/// The visual treatment used to render the cracked-glass fracture lines.
///
/// All keep the cracks readable over the frosted capture by drawing the highlights
/// as *additive* light rather than flat white paint — that is what makes a fracture
/// read as glass catching light instead of a dark drawn line. They differ only in
/// how far the effect is pushed.
///
/// Selectable in Preferences so the styles can be compared live in a real break.
/// The selection and the other-than-chosen styles are temporary scaffolding to be
/// collapsed to the winning treatment once picked (see ``CrackedGlassCanvas``).
enum CrackStyle: String, CaseIterable, Identifiable {
    /// Additive fracture lines over a thin, offset dark stroke for depth.
    case glint
    /// ``glint`` plus bright twinkles where secondary cracks branch off.
    case sparkle
    /// ``glint`` plus a soft blurred glow hugging the main cracks (wet sheen).
    case glossy

    var id: Self { self }

    var label: String {
        switch self {
        case .glint: "Glint"
        case .sparkle: "Sparkle"
        case .glossy: "Glossy"
        }
    }
}
