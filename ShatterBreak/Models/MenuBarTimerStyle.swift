import Foundation

/// Controls whether — and at what precision — the remaining time appears next to
/// the menu bar icon.
///
/// `minutes` is the power-save middle ground between hiding the timer and the
/// full per-second display: the label redraws once a minute instead of every
/// second, switching to seconds only for the final minute.
///
/// The lowercase `rawValue` of each case is the string persisted in user defaults;
/// an unrecognized stored value decodes to `nil`, letting the read site fall back
/// to a default rather than trusting a corrupt preference.
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

    /// The countdown rendering this style asks for; `nil` when the timer is hidden.
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
