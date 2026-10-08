import Foundation
import Testing

@testable import ShatterBreak

@Suite("Menu bar warning", .timeLimit(.minutes(1)))
struct MenuBarWarningTests {
    @Test("The warning covers the last lead seconds of running work, ends included")
    func theWarningCoversTheLeadWindow() {
        #expect(MenuBarWarning.isActive(mode: .running, remaining: 61, leadSecs: 60) == false)
        #expect(MenuBarWarning.isActive(mode: .running, remaining: 60, leadSecs: 60))
        #expect(MenuBarWarning.isActive(mode: .running, remaining: 0.5, leadSecs: 60))
        #expect(MenuBarWarning.isActive(mode: .running, remaining: 0, leadSecs: 60) == false)
    }

    @Test("Only running work warns", arguments: [
        TimerState.Mode.idle, .paused, .resting, .postponedWork, .awaitingReturn
    ])
    func onlyRunningWorkWarns(mode: TimerState.Mode) {
        #expect(MenuBarWarning.isActive(mode: mode, remaining: 30, leadSecs: 60) == false)
    }

    @Test("A lead as long as the session highlights all of it, and Preferences says so")
    func aLeadAsLongAsTheSessionCoversIt() {
        #expect(MenuBarWarning.coversWholeSession(leadSecs: 300, workDurationSecs: 300))
        #expect(MenuBarWarning.coversWholeSession(leadSecs: 300, workDurationSecs: 120))
        #expect(MenuBarWarning.coversWholeSession(leadSecs: 300, workDurationSecs: 301) == false)
        #expect(MenuBarWarning.coversWholeSession(leadSecs: 0, workDurationSecs: 5) == false)
    }

    @Test("A zero lead switches the warning off")
    func aZeroLeadIsOff() {
        #expect(MenuBarWarning.isActive(mode: .running, remaining: 30, leadSecs: 0) == false)
        #expect(MenuBarWarning.delayToStart(forRemaining: 30, leadSecs: 0) == nil)
    }

    @Test("The wait for the warning ends where it begins")
    func theWaitEndsWhereTheWarningBegins() {
        #expect(MenuBarWarning.delayToStart(forRemaining: 100, leadSecs: 60) == 40)
        #expect(MenuBarWarning.delayToStart(forRemaining: 60, leadSecs: 60) == nil)
        #expect(MenuBarWarning.delayToStart(forRemaining: 10, leadSecs: 60) == nil)
    }

    @Test("A stored lead outside the picker's choices resets to the default")
    func anUnknownStoredLeadResetsToTheDefault() {
        let defaults = InMemoryKeyValueStore()
        defaults.set(45, forKey: PreferenceKeys.menuBarWarningLeadSecs)

        #expect(MenuBarWarning.storedLead(in: defaults) == PreferenceDefaults.menuBarWarningLeadSecs)
        #expect(defaults.object(forKey: PreferenceKeys.menuBarWarningLeadSecs) == nil)
    }

    @Test("A stored lead from the picker's choices is kept, off included", arguments: MenuBarWarning.leadChoices)
    func aKnownStoredLeadIsKept(lead: Int) {
        let defaults = InMemoryKeyValueStore()
        defaults.set(lead, forKey: PreferenceKeys.menuBarWarningLeadSecs)

        #expect(MenuBarWarning.storedLead(in: defaults) == lead)
    }

    @Test("With nothing stored the lead is the default")
    func nothingStoredIsTheDefault() {
        #expect(MenuBarWarning.storedLead(in: InMemoryKeyValueStore()) == PreferenceDefaults.menuBarWarningLeadSecs)
    }
}
