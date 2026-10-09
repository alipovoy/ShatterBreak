import Foundation

enum MenuBarWarning {
    static let leadChoices = [0, 30, 60, 120, 300]

    static func storedLead(in defaults: any KeyValueStore) -> Int {
        guard let stored = defaults.object(forKey: PreferenceKeys.menuBarWarningLeadSecs) else {
            return PreferenceDefaults.menuBarWarningLeadSecs
        }
        guard let lead = stored as? Int, leadChoices.contains(lead) else {
            defaults.removeObject(forKey: PreferenceKeys.menuBarWarningLeadSecs)
            return PreferenceDefaults.menuBarWarningLeadSecs
        }
        return lead
    }

    static func isActive(mode: TimerState.Mode, remaining: TimeInterval, leadSecs: Int) -> Bool {
        mode == .running && leadSecs > 0 && remaining > 0 && remaining <= TimeInterval(leadSecs)
    }

    /// Through ``isActive(mode:remaining:leadSecs:)``, so the Preferences hint cannot disagree
    /// with the item about where the lead begins.
    static func coversWholeSession(leadSecs: Int, workDurationSecs: TimeInterval) -> Bool {
        isActive(mode: .running, remaining: workDurationSecs, leadSecs: leadSecs)
    }

    static func delayToStart(forRemaining remaining: TimeInterval, leadSecs: Int) -> TimeInterval? {
        guard leadSecs > 0, remaining > TimeInterval(leadSecs) else { return nil }
        return remaining - TimeInterval(leadSecs)
    }

    @MainActor
    static func driveStart(for state: TimerState, leadSecs: Int, onTick: (Date) -> Void) async {
        while Task.isCancelled == false {
            let referenceDate = state.now().date
            onTick(referenceDate)

            guard state.mode == .running,
                  let delay = delayToStart(forRemaining: state.timeRemaining(at: referenceDate), leadSecs: leadSecs)
            else { return }

            do {
                try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(100))
            } catch {
                return
            }
        }
    }
}
