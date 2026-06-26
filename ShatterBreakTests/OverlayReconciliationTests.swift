import CoreGraphics
import Testing

@testable import ShatterBreak

@Suite("Overlay reconciliation planning", .tags(.overlays))
struct OverlayReconciliationTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    private let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondaryFrame = CGRect(x: 1920, y: 0, width: 1280, height: 800)

    @Test("an unchanged configuration plans no changes")
    func unchangedConfigurationIsEmpty() {
        let plan = OverlayReconciliation.plan(
            currentWindows: [primaryDisplay: primaryFrame, secondaryDisplay: secondaryFrame],
            availableScreens: [
                ScreenInfo(displayID: primaryDisplay, frame: primaryFrame),
                ScreenInfo(displayID: secondaryDisplay, frame: secondaryFrame)
            ]
        )

        #expect(plan.isEmpty)
    }

    @Test("unplugging the main display tears down only its window")
    func disconnectingMainDisplayRemovesItsWindow() {
        // The main display (1) is unplugged; only the secondary (2) remains, keeping its
        // own frame. The surviving window must not move or resize — it already fits.
        let plan = OverlayReconciliation.plan(
            currentWindows: [primaryDisplay: primaryFrame, secondaryDisplay: secondaryFrame],
            availableScreens: [ScreenInfo(displayID: secondaryDisplay, frame: secondaryFrame)]
        )

        #expect(plan.removed == [primaryDisplay])
        #expect(plan.added.isEmpty)
        #expect(plan.reframed.isEmpty)
    }

    @Test("opening a clamshell lid adds an overlay for the new display")
    func connectingDisplayAddsOverlay() {
        let newScreen = ScreenInfo(displayID: secondaryDisplay, frame: secondaryFrame)

        let plan = OverlayReconciliation.plan(
            currentWindows: [primaryDisplay: primaryFrame],
            availableScreens: [
                ScreenInfo(displayID: primaryDisplay, frame: primaryFrame),
                newScreen
            ]
        )

        #expect(plan.added == [newScreen])
        #expect(plan.removed.isEmpty)
        #expect(plan.reframed.isEmpty)
    }

    @Test("a display changing resolution reframes its existing window")
    func resolutionChangeReframesWindow() {
        let resized = ScreenInfo(
            displayID: primaryDisplay,
            frame: CGRect(x: 0, y: 0, width: 1280, height: 720)
        )

        let plan = OverlayReconciliation.plan(
            currentWindows: [primaryDisplay: primaryFrame],
            availableScreens: [resized]
        )

        #expect(plan.reframed == [resized])
        #expect(plan.added.isEmpty)
        #expect(plan.removed.isEmpty)
    }

    @Test("a simultaneous swap removes, adds, and reframes in one plan")
    func mixedReconfigurationPlansEveryChange() {
        // Display 1 is unplugged, display 2 is resized, and a fresh display 3 appears.
        let thirdDisplay: CGDirectDisplayID = 3
        let resizedSecondary = ScreenInfo(
            displayID: secondaryDisplay,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let newScreen = ScreenInfo(
            displayID: thirdDisplay,
            frame: CGRect(x: 800, y: 0, width: 1920, height: 1080)
        )

        let plan = OverlayReconciliation.plan(
            currentWindows: [primaryDisplay: primaryFrame, secondaryDisplay: secondaryFrame],
            availableScreens: [resizedSecondary, newScreen]
        )

        #expect(plan.removed == [primaryDisplay])
        #expect(plan.reframed == [resizedSecondary])
        #expect(plan.added == [newScreen])
    }

    @Test("removed display IDs are reported in a stable sorted order")
    func removedDisplaysAreSorted() {
        let plan = OverlayReconciliation.plan(
            currentWindows: [
                3: primaryFrame,
                1: primaryFrame,
                2: primaryFrame
            ],
            availableScreens: []
        )

        #expect(plan.removed == [1, 2, 3])
    }
}
