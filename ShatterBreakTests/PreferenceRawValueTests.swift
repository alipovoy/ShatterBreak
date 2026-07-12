import Testing

@testable import ShatterBreak

private let effectTypeRawValues: [(value: EffectType, rawValue: String)] = [
    (.shatter, "shatter"),
    (.fogged, "fogged"),
    (.dimmed, "dimmed")
]

private let workStartModeRawValues: [(value: WorkStartMode, rawValue: String)] = [
    (.automatic, "automatic"),
    (.manual, "manual")
]

private let menuBarTimerStyleRawValues: [(value: MenuBarTimerStyle, rawValue: String)] = [
    (.off, "off"),
    (.minutes, "minutes"),
    (.seconds, "seconds")
]

/// `EffectType`, `WorkStartMode`, and `MenuBarTimerStyle` persist their lowercase
/// `rawValue` in user defaults. These tests pin those strings so a case rename can't silently change a
/// stored key, and confirm that any unrecognized value (now including the formerly
/// accepted capitalized aliases) decodes to `nil`, so the read sites fall back to a
/// default instead of trusting a corrupt preference.
@Suite("Preference raw-value stability", .timeLimit(.minutes(1)))
struct PreferenceRawValueTests {
    @Test("EffectType round-trips its persisted raw value", arguments: effectTypeRawValues)
    func effectTypeRoundTripsRawValue(_ testCase: (value: EffectType, rawValue: String)) {
        #expect(testCase.value.rawValue == testCase.rawValue, "EffectType raw values must stay stable.")
        #expect(EffectType(rawValue: testCase.rawValue) == testCase.value, "EffectType should decode its raw value.")
    }

    @Test(
        "EffectType rejects unrecognized raw values",
        arguments: ["", "Shatter", "Fogged", "Dimmed", "overlay", "frosted", "fog", "sparkle"]
    )
    func effectTypeRejectsUnknownRawValues(rawValue: String) {
        #expect(EffectType(rawValue: rawValue) == nil, "EffectType should reject \"\(rawValue)\".")
    }

    @Test("WorkStartMode round-trips its persisted raw value", arguments: workStartModeRawValues)
    func workStartModeRoundTripsRawValue(_ testCase: (value: WorkStartMode, rawValue: String)) {
        #expect(testCase.value.rawValue == testCase.rawValue, "WorkStartMode raw values must stay stable.")
        #expect(
            WorkStartMode(rawValue: testCase.rawValue) == testCase.value,
            "WorkStartMode should decode its raw value."
        )
    }

    @Test(
        "WorkStartMode rejects unrecognized raw values",
        arguments: ["", "Automatic", "Manual", "auto", "Manuel"]
    )
    func workStartModeRejectsUnknownRawValues(rawValue: String) {
        #expect(WorkStartMode(rawValue: rawValue) == nil, "WorkStartMode should reject \"\(rawValue)\".")
    }

    @Test("MenuBarTimerStyle round-trips its persisted raw value", arguments: menuBarTimerStyleRawValues)
    func menuBarTimerStyleRoundTripsRawValue(_ testCase: (value: MenuBarTimerStyle, rawValue: String)) {
        #expect(testCase.value.rawValue == testCase.rawValue, "MenuBarTimerStyle raw values must stay stable.")
        #expect(
            MenuBarTimerStyle(rawValue: testCase.rawValue) == testCase.value,
            "MenuBarTimerStyle should decode its raw value."
        )
    }

    @Test(
        "MenuBarTimerStyle rejects unrecognized raw values",
        arguments: ["", "Off", "Minutes", "Seconds", "hidden", "true", "false"]
    )
    func menuBarTimerStyleRejectsUnknownRawValues(rawValue: String) {
        #expect(MenuBarTimerStyle(rawValue: rawValue) == nil, "MenuBarTimerStyle should reject \"\(rawValue)\".")
    }
}
