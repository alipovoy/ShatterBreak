import Foundation

/// Defines the types of visual effects available for the working state.
enum EffectType: CaseIterable, Identifiable, RawRepresentable {
    case shatter
    case overlay

    init?(rawValue: String) {
        switch rawValue {
        case "shatter", "Shatter":
            self = .shatter
        case "overlay", "Overlay":
            self = .overlay
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .shatter:
            "shatter"
        case .overlay:
            "overlay"
        }
    }

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .shatter:
            .effectShatter
        case .overlay:
            .effectOverlay
        }
    }
}
