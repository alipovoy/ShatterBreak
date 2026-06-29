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

    @Test("effect type reflects the stored dimmed preference")
    func effectTypeReadsStoredDimmed() {
        let environment = TestEnvironment()
        environment.defaults.set(EffectType.dimmed.rawValue, forKey: PreferenceKeys.effectType)
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .dimmed)
    }

    @Test("effect type reflects the stored fogged preference")
    func effectTypeReadsStoredFogged() {
        let environment = TestEnvironment()
        environment.defaults.set(EffectType.fogged.rawValue, forKey: PreferenceKeys.effectType)
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .fogged)
    }

    @Test("effect type falls back to shatter for an unrecognized preference")
    func effectTypeFallsBackForUnknownValue() {
        let environment = TestEnvironment()
        environment.defaults.set("sparkle", forKey: PreferenceKeys.effectType)
        let manager = environment.makeOverlayManager()

        #expect(manager.selectedEffectType == .shatter)
    }

    @Test("shatter without Screen Recording permission resolves to fogged")
    func shatterWithoutPermissionResolvesToFogged() {
        #expect(
            OverlayManager.resolveEffectType(selected: .shatter, hasScreenRecordingPermission: false) == .fogged,
            "Shatter must fall back to fogged glass when it cannot capture the screen."
        )
    }

    @Test("shatter with Screen Recording permission stays shatter")
    func shatterWithPermissionStaysShatter() {
        #expect(
            OverlayManager.resolveEffectType(selected: .shatter, hasScreenRecordingPermission: true) == .shatter
        )
    }

    @Test(
        "fogged and dimmed never depend on Screen Recording permission",
        arguments: [EffectType.fogged, .dimmed], [true, false]
    )
    func permissionlessEffectsAreUnaffected(selected: EffectType, hasPermission: Bool) {
        let resolved = OverlayManager.resolveEffectType(
            selected: selected,
            hasScreenRecordingPermission: hasPermission
        )
        #expect(resolved == selected, "\(selected) needs no permission, so it should be presented as chosen.")
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
