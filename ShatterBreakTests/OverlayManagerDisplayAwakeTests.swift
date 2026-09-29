import AppKit
import Testing

@testable import ShatterBreak

@Suite("OverlayManager display-awake gating", .tags(.overlays))
@MainActor
struct OverlayManagerDisplayAwakeTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    @Test("a break skips a window for a display that is asleep")
    func sleepingDisplayGetsNoWindow() {
        let environment = TestEnvironment()
        environment.asleepDisplays = [primaryDisplay]
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(screens: screens)
        defer { manager.dismiss() }

        #expect(manager.awakeScreens().map(\.displayID) == [secondaryDisplay])

        manager.show(environment.makeTimerState(), style: .animated)

        #expect(manager.overlayStates[primaryDisplay] == nil, "The asleep display must get no overlay window.")
        #expect(manager.overlayStates[secondaryDisplay] != nil, "The awake display still gets its overlay.")

        environment.asleepDisplays.insert(secondaryDisplay)
        #expect(manager.awakeScreens().isEmpty, "Once every display is asleep, none is presentable.")
    }

    @Test("a display asleep at break start joins settled once it wakes")
    func sleepingDisplayJoinsOnWake() {
        let environment = TestEnvironment()
        environment.asleepDisplays = [secondaryDisplay]
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            screens: screens
        )
        defer { manager.dismiss() }

        manager.show(environment.makeTimerState(), style: .animated)
        #expect(manager.overlayStates[secondaryDisplay] == nil, "Asleep at break start, so no window yet.")

        environment.asleepDisplays.remove(secondaryDisplay)
        manager.displaysDidChange()

        #expect(
            manager.overlayStates[secondaryDisplay]?.settled == true,
            "A display joining after the break began must not replay the entrance."
        )
        #expect(
            manager.overlayStates[primaryDisplay]?.settled == false,
            "The original overlay keeps the entrance it already played."
        )
    }

    @Test("a display already on screen is left alone when the machine sleeps and wakes")
    func awakeDisplayUnaffectedBySleepWakeNotifications() {
        let environment = TestEnvironment()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            screens: screens
        )
        defer { manager.dismiss() }

        manager.show(environment.makeTimerState(), style: .animated)

        manager.displaysDidChange()

        #expect(manager.overlayStates[primaryDisplay]?.settled == false, "Its window was never torn down.")
    }

    @Test("a display asleep behind an unrelated reconfiguration keeps its window")
    func sleepingDisplayIsNotTornDownByAnUnrelatedReconfiguration() {
        let environment = TestEnvironment()
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            screens: screens
        )
        defer { manager.dismiss() }

        manager.show(environment.makeTimerState(), style: .animated)

        // The primary sleeps, then an unrelated reconfiguration.
        environment.asleepDisplays.insert(primaryDisplay)
        manager.displaysDidChange()

        #expect(
            manager.overlayStates[primaryDisplay] != nil,
            "Asleep is not unplugged: the window must survive a reconfiguration it had no part in."
        )
    }
}
