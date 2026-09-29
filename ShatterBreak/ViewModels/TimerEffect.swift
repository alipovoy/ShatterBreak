import Foundation

/// Something the world must do because the plan changed. The reducer decides what;
/// ``TimerState`` decides when it is safe, so the plan can advance while the screen is dark.
enum TimerEffect: Equatable {
    /// At the head of a work session: a break appears instantly, a consent dialog does not.
    case prepareCapturePermissions
    /// Held until the whole batch is done, so a later `dismissOverlay` or `settleHeldOverlay`
    /// still has its say (issue #112).
    case showOverlay(OverlayPresentationStyle)
    case dismissOverlay
    /// The held break has ended, so it is presented settled.
    case settleHeldOverlay
    case record(StatisticsEvent)
    /// The stop→start boundary, where the opt-in statistics reset applies.
    case resetStatisticsForNewSession
}

enum TimerAction: Equatable {
    case start
    case pause
    case resume
    case stop
    case postpone
    /// The overlay's "I'm back".
    case returnToWork
    /// Advisory only: improves the absence measurement, gates nothing.
    case observedSleep
    /// The system or the display woke. Reconciles first, then retires the absence.
    case observedWake
}

/// Snapshotted as the reducer runs, so Preferences edits apply mid-session.
struct TimerPreferences: Equatable, Sendable {
    var workDuration: TimeInterval
    var restDuration: TimeInterval
    var postponeDuration: TimeInterval
    var autoStartWork: Bool
    /// An absence at least this long counts as the break itself. ``restDuration`` today.
    var awayResetThreshold: TimeInterval
    /// How long before its end a work session counts as worked (issue #71). Zero counts at
    /// the boundary.
    var sessionLead: TimeInterval
}
