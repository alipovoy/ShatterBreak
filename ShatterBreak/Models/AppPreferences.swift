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

    var displayName: String {
        switch self {
        case .shatter:
            "Shatter"
        case .overlay:
            "Overlay"
        }
    }
}

/// Controls whether the work timer should start automatically when a break ends
/// or wait for the user to manually indicate they’ve returned.
enum WorkStartMode: CaseIterable, Identifiable, RawRepresentable {
    case automatic
    case manual

    init?(rawValue: String) {
        switch rawValue {
        case "automatic", "Automatic":
            self = .automatic
        case "manual", "Manual":
            self = .manual
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .automatic:
            "automatic"
        case .manual:
            "manual"
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            "Automatic"
        case .manual:
            "Manual"
        }
    }
}
