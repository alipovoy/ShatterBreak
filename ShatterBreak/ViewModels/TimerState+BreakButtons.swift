import Foundation

/// Break-overlay action-button visibility: pure functions of `mode`, the break time and the
/// user's preferences, read live so Preferences edits apply mid-session.
extension TimerState {
    /// How long a single postpone pushes the break back by, unless a test overrode it.
    var postponeDurationSecs: Double {
        postponeDurationOverride
            ?? defaults.duration(forKey: PreferenceKeys.postponeDurationSecs,
                                 default: PreferenceDefaults.postponeDurationSecs)
    }

    /// Offered only in the break's opening window, until `postponeWindowSecs` has elapsed.
    /// A window longer than the break keeps the button up for all of it.
    func showsPostponeButton(at referenceDate: Date) -> Bool {
        guard canPostpone, allowPostpone else { return false }
        let elapsed = restDurationSecs - timeRemaining(at: referenceDate)
        return elapsed < postponeWindowSecs
    }

    /// Always shown once a manual-mode break has ended (`awaitingReturn`); during a break it
    /// appears in the closing `earlyReturnLeadSecs`, when enabled.
    func showsReturnButton(at referenceDate: Date) -> Bool {
        switch mode {
        case .awaitingReturn:
            return true
        case .resting:
            return allowEarlyReturn && timeRemaining(at: referenceDate) <= earlyReturnLeadSecs
        default:
            return false
        }
    }

    /// Button visibility at the tick source's current moment, for views and tests.
    var showsPostponeButton: Bool { showsPostponeButton(at: clock.instant.date) }
    var showsReturnButton: Bool { showsReturnButton(at: clock.instant.date) }

    // MARK: - Live preference reads

    private var allowPostpone: Bool {
        (defaults.object(forKey: PreferenceKeys.allowPostpone) as? Bool) ?? PreferenceDefaults.allowPostpone
    }

    private var allowEarlyReturn: Bool {
        (defaults.object(forKey: PreferenceKeys.allowEarlyReturn) as? Bool) ?? PreferenceDefaults.allowEarlyReturn
    }

    private var postponeWindowSecs: Double {
        defaults.duration(forKey: PreferenceKeys.postponeWindowSecs,
                          default: PreferenceDefaults.postponeWindowSecs)
    }

    private var earlyReturnLeadSecs: Double {
        defaults.duration(forKey: PreferenceKeys.earlyReturnLeadSecs,
                          default: PreferenceDefaults.earlyReturnLeadSecs)
    }

}
