import Foundation

/// Break-overlay action-button visibility and the live preference reads that drive it.
///
/// Split out from ``TimerState`` so the state machine file stays focused; these members
/// are pure functions of `mode`, the elapsed/remaining break time, and the user's
/// preferences (read live so Preferences edits apply mid-session).
extension TimerState {
    /// How long a single postpone pushes the break back by.
    ///
    /// Read live from preferences so edits in the Preferences window take effect
    /// immediately, unless a test supplied an explicit override at init.
    var postponeDurationSecs: Double {
        postponeDurationOverride
            ?? livePref(PreferenceKeys.postponeDurationSecs, default: PreferenceDefaults.postponeDurationSecs)
    }

    /// Whether the Postpone button should be visible at `referenceDate`.
    ///
    /// Offered only during the opening window of the break: from the moment rest
    /// begins until `postponeWindowSecs` has elapsed. A window longer than the break
    /// simply keeps the button visible for the whole break.
    func showsPostponeButton(at referenceDate: Date) -> Bool {
        guard canPostpone, allowPostpone else { return false }
        let elapsed = restDurationSecs - timeRemaining(at: referenceDate)
        return elapsed < postponeWindowSecs
    }

    /// Whether the "I'm back" button should be visible at `referenceDate`.
    ///
    /// Always shown once a manual-mode break has ended (`awaitingReturn`). During the
    /// break it appears early — in the closing `earlyReturnLeadSecs` — when enabled,
    /// in both automatic and manual work-start modes.
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
    var showsPostponeButton: Bool { showsPostponeButton(at: countdown.now) }
    var showsReturnButton: Bool { showsReturnButton(at: countdown.now) }

    // MARK: - Live preference reads

    private var allowPostpone: Bool {
        (defaults.object(forKey: PreferenceKeys.allowPostpone) as? Bool) ?? PreferenceDefaults.allowPostpone
    }

    private var allowEarlyReturn: Bool {
        (defaults.object(forKey: PreferenceKeys.allowEarlyReturn) as? Bool) ?? PreferenceDefaults.allowEarlyReturn
    }

    private var postponeWindowSecs: Double {
        livePref(PreferenceKeys.postponeWindowSecs, default: PreferenceDefaults.postponeWindowSecs)
    }

    private var earlyReturnLeadSecs: Double {
        livePref(PreferenceKeys.earlyReturnLeadSecs, default: PreferenceDefaults.earlyReturnLeadSecs)
    }

    /// Reads a duration preference live, falling back to `defaultValue` when unset.
    /// Mirrors `TimerState`'s init-time duration loading but without caching, so
    /// Preferences edits apply mid-session.
    private func livePref(_ key: String, default defaultValue: Double) -> Double {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : defaultValue
    }
}
