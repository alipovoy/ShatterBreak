import Foundation

/// Whether, and how precisely, the countdown shows beside the menu bar icon. `minutes`
/// redraws once a minute to save power, switching to seconds for the last one.
enum MenuBarTimerStyle: String, CaseIterable, Identifiable {
    case off
    case minutes
    case seconds

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .off:
            .menuBarTimerStyleOff
        case .minutes:
            .menuBarTimerStyleMinutes
        case .seconds:
            .menuBarTimerStyleSeconds
        }
    }

    var countdownDisplayStyle: CountdownDisplayStyle? {
        switch self {
        case .off:
            nil
        case .minutes:
            .minutes
        case .seconds:
            .seconds
        }
    }
}
