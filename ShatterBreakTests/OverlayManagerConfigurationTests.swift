import AppKit
import Testing

@testable import ShatterBreak

@Suite("OverlayManager configuration", .tags(.overlays))
@MainActor
struct OverlayManagerConfigurationTests {
    @Test("effect type defaults to shatter when no preference is stored")
    func effectTypeDefaultsToShatter() {
        let environment = TestEnvironment()
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .shatter)
    }

    @Test("effect type reflects the stored overlay preference")
    func effectTypeReadsStoredOverlay() {
        let environment = TestEnvironment()
        environment.defaults.set(EffectType.overlay.rawValue, forKey: PreferenceKeys.effectType)
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .overlay)
    }

    @Test("effect type falls back to shatter for an unrecognized preference")
    func effectTypeFallsBackForUnknownValue() {
        let environment = TestEnvironment()
        environment.defaults.set("sparkle", forKey: PreferenceKeys.effectType)
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .shatter)
    }

    @Test("soft overlay is preferred when no preference is stored")
    func softOverlayDefaultsToTrue() {
        let environment = TestEnvironment()
        let manager = environment.makeOverlayManager()

        #expect(manager.prefersSoftOverlay)
        #expect(manager.overlayWindowLevel == NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1))
    }

    @Test("disabling soft overlay raises the window to screen-saver level")
    func hardOverlayUsesScreenSaverLevel() {
        let environment = TestEnvironment()
        environment.defaults.set(false, forKey: PreferenceKeys.softOverlay)
        let manager = environment.makeOverlayManager()

        #expect(manager.prefersSoftOverlay == false)
        #expect(manager.overlayWindowLevel == .screenSaver)
    }

    @Test("enabling soft overlay keeps the window just below the menu bar")
    func softOverlayUsesBelowMenuBarLevel() {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: PreferenceKeys.softOverlay)
        let manager = environment.makeOverlayManager()

        #expect(manager.prefersSoftOverlay)
        #expect(manager.overlayWindowLevel == NSWindow.Level(Int(NSWindow.Level.mainMenu.rawValue) - 1))
    }
}
