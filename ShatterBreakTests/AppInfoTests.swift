import Testing

@testable import ShatterBreak

@Suite("AppInfo")
struct AppInfoTests {
    @Test("reads each field from the info dictionary")
    func readsAllFields() {
        let info = AppInfo(info: [
            "CFBundleDisplayName": "ShatterBreak",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
            "AppBuildHash": "abc1234"
        ])

        #expect(info.name == "ShatterBreak")
        #expect(info.version == "1.2.3")
        #expect(info.build == "42")
        #expect(info.commitHash == "abc1234")
    }

    @Test("prefers the display name over the bundle name")
    func prefersDisplayName() {
        let info = AppInfo(info: [
            "CFBundleDisplayName": "ShatterBreak",
            "CFBundleName": "ShatterBreak Dev"
        ])

        #expect(info.name == "ShatterBreak")
    }

    @Test("falls back to the bundle name when no display name is present")
    func fallsBackToBundleName() {
        let info = AppInfo(info: ["CFBundleName": "ShatterBreak Dev"])

        #expect(info.name == "ShatterBreak Dev")
    }

    @Test("uses sensible fallbacks when keys are missing")
    func usesFallbacks() {
        let info = AppInfo(info: [:])

        #expect(info.name == "ShatterBreak")
        #expect(info.version == "—")
        #expect(info.build == "—")
        #expect(info.commitHash == "dev")
    }

    @Test("uses fallbacks when the info dictionary is nil")
    func handlesNilDictionary() {
        let info = AppInfo(info: nil)

        #expect(info.name == "ShatterBreak")
        #expect(info.commitHash == "dev")
    }
}
