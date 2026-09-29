import Foundation

/// One default per ``PreferenceKeys`` entry, shared by `@AppStorage` and the models.
enum PreferenceDefaults {
    static let allowEarlyReturn = false
    static let allowPostpone = false
    static let autoStartOnLaunch = false
    static let countSessionEarly = false
    static let earlyReturnLeadSecs: Double = 30
    static let effectType: EffectType = .shatter
    static let menuBarTimerStyle: MenuBarTimerStyle = .off
    static let playSound = true
    static let postponeDurationSecs: Double = 60
    static let postponeWindowSecs: Double = 60
    static let reduceMotion = false
    static let resetStatisticsOnStart = false
    static let restDurationSecs: Double = 300
    static let sessionLeadSecs: Double = 180
    static let softOverlay = true
    static let statisticsExpanded = true
    static let trackStatistics = false
    static let workDurationSecs: Double = 1500
    static let workStartMode: WorkStartMode = .automatic
}
