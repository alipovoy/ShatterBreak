import Foundation

/// The session-statistics counters (issue #10), plus the moment the current tally began.
///
/// Persisted as a single JSON blob under `PreferenceKeys.sessionStatistics` so a reset
/// replaces the whole value atomically and future fields version cleanly.
struct SessionStatistics: Codable, Equatable {
    var workSessionsCompleted = 0
    var breaksCompleted = 0
    var postponesUsed = 0
    var earlyReturns = 0
    var since: Date
}
