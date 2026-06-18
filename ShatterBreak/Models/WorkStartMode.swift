import Foundation

/// Controls whether the work timer should start automatically when a break ends
/// or wait for the user to manually indicate they have returned.
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

    var displayName: LocalizedStringResource {
        switch self {
        case .automatic:
            .workStartModeAutomatic
        case .manual:
            .workStartModeManual
        }
    }
}
