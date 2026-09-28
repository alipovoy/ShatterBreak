import Foundation

/// Accepted ranges, in seconds. The minimum and the work maximum match the ends of
/// ``PiecewiseTimer``'s slider.
enum DurationBounds {
    static let minimumSecs: Double = 5
    static let workMaximumSecs: Double = 7200
    static let restMaximumSecs: Double = 3600
    static let postponeWindowMaximumSecs: Double = 600
    static let postponeDurationMaximumSecs: Double = 600
    static let earlyReturnLeadMaximumSecs: Double = 600
    static let sessionLeadMaximumSecs: Double = 600
}
