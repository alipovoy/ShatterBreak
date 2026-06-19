import Testing

@testable import ShatterBreak

private let effectTypeRawValueCases: [(rawValue: String, expected: EffectType)] = [
    ("shatter", .shatter),
    ("Shatter", .shatter),
    ("overlay", .overlay),
    ("Overlay", .overlay)
]

private let workStartModeRawValueCases: [(rawValue: String, expected: WorkStartMode)] = [
    ("automatic", .automatic),
    ("Automatic", .automatic),
    ("manual", .manual),
    ("Manual", .manual)
]

/// `EffectType` and `WorkStartMode` store lowercase raw values but must keep decoding the
/// older capitalized values for backwards compatibility (requirements §9).
@Suite("Legacy raw-value compatibility", .timeLimit(.minutes(1)))
struct RawValueCompatibilityTests {
    @Test("EffectType decodes lowercase and legacy capitalized raw values", arguments: effectTypeRawValueCases)
    func effectTypeDecodesLegacyRawValues(_ testCase: (rawValue: String, expected: EffectType)) {
        #expect(
            EffectType(rawValue: testCase.rawValue) == testCase.expected,
            "EffectType should decode \"\(testCase.rawValue)\" to \(testCase.expected)."
        )
    }

    @Test("EffectType rejects unknown raw values", arguments: ["", "SHATTER", "Shimmer", "overlays"])
    func effectTypeRejectsUnknownRawValues(rawValue: String) {
        #expect(EffectType(rawValue: rawValue) == nil, "EffectType should reject \"\(rawValue)\".")
    }

    @Test("EffectType stores lowercase raw values")
    func effectTypeStoresLowercaseRawValues() {
        #expect(EffectType.shatter.rawValue == "shatter", "EffectType should persist lowercase raw values.")
        #expect(EffectType.overlay.rawValue == "overlay", "EffectType should persist lowercase raw values.")
    }

    @Test("WorkStartMode decodes lowercase and legacy capitalized raw values", arguments: workStartModeRawValueCases)
    func workStartModeDecodesLegacyRawValues(_ testCase: (rawValue: String, expected: WorkStartMode)) {
        #expect(
            WorkStartMode(rawValue: testCase.rawValue) == testCase.expected,
            "WorkStartMode should decode \"\(testCase.rawValue)\" to \(testCase.expected)."
        )
    }

    @Test("WorkStartMode rejects unknown raw values", arguments: ["", "AUTOMATIC", "auto", "Manuel"])
    func workStartModeRejectsUnknownRawValues(rawValue: String) {
        #expect(WorkStartMode(rawValue: rawValue) == nil, "WorkStartMode should reject \"\(rawValue)\".")
    }

    @Test("WorkStartMode stores lowercase raw values")
    func workStartModeStoresLowercaseRawValues() {
        #expect(
            WorkStartMode.automatic.rawValue == "automatic",
            "WorkStartMode should persist lowercase raw values."
        )
        #expect(WorkStartMode.manual.rawValue == "manual", "WorkStartMode should persist lowercase raw values.")
    }
}
