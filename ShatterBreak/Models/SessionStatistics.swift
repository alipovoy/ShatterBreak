import Foundation

/// Persisted as one JSON value, so a reset replaces it whole.
struct SessionStatistics: Codable, Equatable {
    var workSessionsCompleted = 0
    var breaksCompleted = 0
    var postponesUsed = 0
    var earlyReturns = 0
    var since: Date
}
