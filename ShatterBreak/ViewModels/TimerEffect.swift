import Foundation

/// Something the world must do because the plan changed.
///
/// The reducer decides *what* should happen; an executor decides *when it is safe*.
/// Keeping the two apart is what lets the plan advance during a DarkWake — the display is
/// off but time really did pass — while the break overlay waits for a screen to be shown
/// on (#99, #107).
enum TimerEffect: Equatable {
    /// Settle screen-capture consent at the head of a work session, well before a break
    /// needs it (#90).
    case prepareCapturePermissions
    case showOverlay(OverlayPresentationStyle)
    case dismissOverlay
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
    /// The system or the display went to sleep. Advisory only — it improves the absence
    /// measurement, it does not gate anything.
    case observedSleep
    /// The system or the display woke. Reconciles first, then retires the absence.
    case observedWake
}

/// The preference values the reducer needs, snapshotted at the moment it runs.
///
/// A snapshot rather than a stored copy so edits in Preferences apply mid-session, which
/// is what the live reads in the old `TimerState` were for.
struct TimerPreferences: Equatable, Sendable {
    var workDuration: TimeInterval
    var restDuration: TimeInterval
    var postponeDuration: TimeInterval
    /// Whether work auto-starts once a break ends.
    var autoStartWork: Bool
    /// An absence at least this long counts as the break itself (#69).
    ///
    /// A parameter from day one but always passed ``restDuration``: making it configurable
    /// (#71) is then a preference read, not a redesign.
    var awayResetThreshold: TimeInterval
}
