import Testing

@testable import ShatterBreak

/// These strings are what users have stored; a rename silently resets their choice.
@Suite("Preference raw values")
struct PreferenceRawValueTests {
    @Test("stored raw values stay stable")
    func rawValuesAreStable() {
        #expect(EffectType.allCases.map(\.rawValue) == ["shatter", "fogged", "dimmed"])
        #expect(MenuBarTimerStyle.allCases.map(\.rawValue) == ["off", "minutes", "seconds"])
        #expect(WorkStartMode(rawValue: "automatic") == .automatic)
        #expect(WorkStartMode(rawValue: "manual") == .manual)
    }
}
