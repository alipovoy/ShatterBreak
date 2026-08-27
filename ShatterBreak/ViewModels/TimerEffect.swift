import Foundation

/// Something the world must do because the plan changed.
///
/// The reducer decides *what*, the executor *when it is safe* — which is what lets the plan
/// advance during a DarkWake while the overlay waits for a screen.
enum TimerEffect: Equatable {
    /// Settle screen-capture consent at the head of a work session, well before a break
    /// needs it: presentation is instantaneous, a system dialog is not.
    case prepareCapturePermissions
    case showOverlay(OverlayPresentationStyle)
    case dismissOverlay
    /// A held presentation is out of date: the break it would announce has ended, so present
    /// it settled, with no shake and no sound.
    case settleHeldOverlay
    case record(StatisticsEvent)
    /// The stop→start boundary, where the opt-in statistics reset applies.
    case resetStatisticsForNewSession
}

/// Something the user (or the system) did, as a value the reducer can be tested against.
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

/// The preference values the reducer needs, snapshotted at the moment it runs so that
/// edits in Preferences apply mid-session.
struct TimerPreferences: Equatable, Sendable {
    var workDuration: TimeInterval
    var restDuration: TimeInterval
    var postponeDuration: TimeInterval
    /// Whether work auto-starts once a break ends.
    var autoStartWork: Bool
    /// An absence at least this long counts as the break itself. Always passed
    /// ``restDuration`` today; a parameter so making it configurable stays a one-line change.
    var awayResetThreshold: TimeInterval
}
