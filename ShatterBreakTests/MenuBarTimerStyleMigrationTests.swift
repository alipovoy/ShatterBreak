import Testing

@testable import ShatterBreak

/// The `showTimerInMenuBar` boolean was replaced by the three-way
/// ``MenuBarTimerStyle`` preference. These tests pin the one-time migration:
/// an enabled legacy timer keeps its per-second display, everything else is
/// left alone, and a value already stored under the new key always wins.
@Suite("Menu bar timer style migration", .timeLimit(.minutes(1)))
struct MenuBarTimerStyleMigrationTests {
    private let defaults = InMemoryKeyValueStore()

    @Test("Legacy enabled timer migrates to the seconds style")
    func enabledLegacyTimerMigratesToSeconds() {
        defaults.set(true, forKey: PreferenceKeys.showTimerInMenuBar)

        MenuBarTimerStyle.migrateLegacyShowTimerPreference(in: defaults)

        #expect(defaults.string(forKey: PreferenceKeys.menuBarTimerStyle) == "seconds")
    }

    @Test("Legacy disabled timer leaves the new key unset")
    func disabledLegacyTimerLeavesNewKeyUnset() {
        defaults.set(false, forKey: PreferenceKeys.showTimerInMenuBar)

        MenuBarTimerStyle.migrateLegacyShowTimerPreference(in: defaults)

        #expect(defaults.object(forKey: PreferenceKeys.menuBarTimerStyle) == nil)
    }

    @Test("Fresh install with neither key stays on the default")
    func freshInstallLeavesNewKeyUnset() {
        MenuBarTimerStyle.migrateLegacyShowTimerPreference(in: defaults)

        #expect(defaults.object(forKey: PreferenceKeys.menuBarTimerStyle) == nil)
    }

    @Test("An existing choice under the new key is never overridden")
    func existingChoiceIsNeverOverridden() {
        defaults.set(true, forKey: PreferenceKeys.showTimerInMenuBar)
        defaults.set(MenuBarTimerStyle.off.rawValue, forKey: PreferenceKeys.menuBarTimerStyle)

        MenuBarTimerStyle.migrateLegacyShowTimerPreference(in: defaults)

        #expect(defaults.string(forKey: PreferenceKeys.menuBarTimerStyle) == "off")
    }
}
