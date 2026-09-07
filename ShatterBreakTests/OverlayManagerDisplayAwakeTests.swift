import AppKit
import Testing

@testable import ShatterBreak

/// Covers per-display awake gating (issue #110): a break must not be drawn onto a
/// display that is asleep, and a display asleep at break start must join once it wakes.
@Suite("OverlayManager display-awake gating", .tags(.overlays))
@MainActor
struct OverlayManagerDisplayAwakeTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    /// A per-display sleep/wake state a test can flip between reconciliation passes.
    @MainActor
    private final class StubDisplayAwakeState {
        private var asleep: Set<CGDirectDisplayID> = []

        func sleep(_ displayID: CGDirectDisplayID) { asleep.insert(displayID) }
        func wake(_ displayID: CGDirectDisplayID) { asleep.remove(displayID) }

        var isAwake: @MainActor (CGDirectDisplayID) -> Bool {
            { [unowned self] displayID in asleep.contains(displayID) == false }
        }
    }

    @Test("a break skips a window for a display that is asleep")
    func sleepingDisplayGetsNoWindow() {
        let environment = TestEnvironment()
        let displays = StubDisplayAwakeState()
        displays.sleep(primaryDisplay)
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            isDisplayAwake: displays.isAwake
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        #expect(manager.overlayStates[primaryDisplay] == nil, "The asleep display must get no overlay window.")
        #expect(manager.overlayStates[secondaryDisplay] != nil, "The awake display still gets its overlay.")
    }

    @Test("awakeScreens() reports none once every display is asleep")
    func awakeScreensEmptyWhenAllAsleep() {
        let environment = TestEnvironment()
        let displays = StubDisplayAwakeState()
        displays.sleep(primaryDisplay)
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            isDisplayAwake: displays.isAwake
        )

        #expect(manager.awakeScreens().isEmpty)
    }

    @Test("a display asleep at break start joins settled once it wakes")
    func sleepingDisplayJoinsOnWake() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        let displays = StubDisplayAwakeState()
        displays.sleep(secondaryDisplay)
        let screens = StubScreens([
            StubScreens.display(primaryDisplay),
            StubScreens.display(secondaryDisplay, x: 1)
        ])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center,
            isDisplayAwake: displays.isAwake
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)
        #expect(manager.overlayStates[secondaryDisplay] == nil, "Asleep at break start, so no window yet.")

        displays.wake(secondaryDisplay)
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
}
