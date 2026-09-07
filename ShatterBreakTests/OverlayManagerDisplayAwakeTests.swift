import AppKit
import Testing

@testable import ShatterBreak

/// Covers per-display awake gating: a break must not be drawn onto a display that is
/// asleep, and a display asleep at break start must join once it wakes.
@Suite("OverlayManager display-awake gating", .tags(.overlays))
@MainActor
struct OverlayManagerDisplayAwakeTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    @Test("a break skips a window for a display that is asleep")
    func sleepingDisplayGetsNoWindow() {
        let environment = TestEnvironment()
        var asleep: Set<CGDirectDisplayID> = [primaryDisplay]
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            isDisplayAwake: { asleep.contains($0) == false }
        )
        defer { manager.dismissOverlays() }

        #expect(manager.awakeScreens().map(\.displayID) == [secondaryDisplay])

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        #expect(manager.overlayStates[primaryDisplay] == nil, "The asleep display must get no overlay window.")
        #expect(manager.overlayStates[secondaryDisplay] != nil, "The awake display still gets its overlay.")

        asleep.insert(secondaryDisplay)
        #expect(manager.awakeScreens().isEmpty, "Once every display is asleep, none is presentable.")
    }

    @Test("a display asleep at break start joins settled once it wakes")
    func sleepingDisplayJoinsOnWake() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        var asleep: Set<CGDirectDisplayID> = [secondaryDisplay]
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center,
            isDisplayAwake: { asleep.contains($0) == false }
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)
        #expect(manager.overlayStates[secondaryDisplay] == nil, "Asleep at break start, so no window yet.")

        asleep.remove(secondaryDisplay)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

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
        let center = NotificationCenter()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        #expect(manager.overlayStates[primaryDisplay]?.settled == false, "Its window was never torn down.")
    }

    @Test("a display asleep behind an unrelated reconfiguration keeps its window")
    func sleepingDisplayIsNotTornDownByAnUnrelatedReconfiguration() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        var asleep: Set<CGDirectDisplayID> = []
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center,
            isDisplayAwake: { asleep.contains($0) == false }
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        // The primary sleeps; some unrelated reconfiguration (e.g. a third display
        // arriving) fires the same notification reconcileOverlays() also answers to.
        asleep.insert(primaryDisplay)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(
            manager.overlayStates[primaryDisplay] != nil,
            "Asleep is not unplugged: the window must survive a reconfiguration it had no part in."
        )
    }
}
