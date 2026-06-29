import Foundation

/// Accepted ranges, in seconds, for the work and rest duration controls.
///
/// These bounds clamp both slider movement and manual text entry in
/// ``DurationSliderView``. Keeping them here is the single source of truth so the
/// menu's two sliders, the view's preview, and the parsing tests cannot drift apart.
enum DurationBounds {
    /// Smallest duration either control accepts. Matches the first slider anchor.
    static let minimumSecs: Double = 5

    /// Largest work duration. Matches the last slider anchor in ``PiecewiseTimer``.
    static let workMaximumSecs: Double = 7200

    /// Largest rest duration.
    static let restMaximumSecs: Double = 3600

    /// Largest window the Postpone button stays visible after a break begins.
    static let postponeWindowMaximumSecs: Double = 600

    /// Largest delay a single postpone pushes the break back by.
    static let postponeDurationMaximumSecs: Double = 600

    /// Largest lead before a break ends that the "I'm back" button appears.
    static let earlyReturnLeadMaximumSecs: Double = 600
}
