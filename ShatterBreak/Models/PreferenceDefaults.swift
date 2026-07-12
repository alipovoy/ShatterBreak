import Foundation

/// Canonical default values for each ``PreferenceKeys`` entry.
///
/// This is the single source of truth shared by the `@AppStorage` declarations in
/// the views and the accessors that read preferences through ``KeyValueStore``
/// (``OverlayManager``, ``TimerState``). Sourcing every default from here keeps the
/// call sites from silently drifting apart when a default changes.
enum PreferenceDefaults {
    static let allowEarlyReturn = false
    static let allowPostpone = false
    static let autoStartOnLaunch = false
    static let earlyReturnLeadSecs: Double = 30
    static let effectType: EffectType = .shatter
    static let menuBarTimerStyle: MenuBarTimerStyle = .off
    static let playSound = true
    static let postponeDurationSecs: Double = 60
    static let postponeWindowSecs: Double = 60
    static let restDurationSecs: Double = 300
    static let softOverlay = true
    static let workDurationSecs: Double = 1500
    static let workStartMode: WorkStartMode = .automatic
}
