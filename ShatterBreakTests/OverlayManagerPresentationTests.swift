import AppKit
import Testing

@testable import ShatterBreak

/// Covers how ``OverlayManager`` presents each display's overlay across a break —
/// in particular that the entrance belongs to the break's start, not to a window
/// (issue #94).
@Suite("OverlayManager presentation", .tags(.overlays))
@MainActor
struct OverlayManagerPresentationTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    @Test("a break's own overlays play the entrance")
    func breakOverlaysPlayTheEntrance() {
        let environment = TestEnvironment()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(captureClient: screens.captureClient)
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        #expect(manager.overlayStates[primaryDisplay]?.settled == false)
    }

    @Test("a display that comes back after the screen slept returns silently (issue #94)")
    func redisplayedScreenComesBackSettled() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        // The display sleeps and drops off, then comes back when the user returns.
        screens.screens = []
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(manager.overlayStates.isEmpty, "A vanished display's overlay is torn down.")

        screens.screens = [StubScreens.display(primaryDisplay)]
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(
            manager.overlayStates[primaryDisplay]?.settled == true,
            """
            An overlay rebuilt mid-break must be settled: replaying the shake and glass \
            sound on every return from sleep is issue #94.
            """
        )
    }

    @Test("a display connected mid-break joins without replaying the entrance")
    func displayAddedMidBreakJoinsSettled() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: false)

        screens.screens.append(StubScreens.display(secondaryDisplay, x: 1))
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(manager.overlayStates[secondaryDisplay]?.settled == true)
        #expect(
            manager.overlayStates[primaryDisplay]?.settled == false,
            "The original overlay keeps the entrance it already played."
        )
    }

    @Test("the break-end window after an absence stays settled on every display")
    func settledSessionStaysSettled() {
        let environment = TestEnvironment()
        let center = NotificationCenter()
        let screens = StubScreens([StubScreens.display(primaryDisplay)])
        let manager = environment.makeOverlayManager(
            captureClient: screens.captureClient,
            notificationCenter: center
        )
        defer { manager.dismissOverlays() }

        manager.showOverlays(state: environment.makeTimerState(), settled: true)

        screens.screens.append(StubScreens.display(secondaryDisplay, x: 1))
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(manager.overlayStates[primaryDisplay]?.settled == true)
        #expect(manager.overlayStates[secondaryDisplay]?.settled == true, "Issue #76's window never plays an entrance.")
    }
}
