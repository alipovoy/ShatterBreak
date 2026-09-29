import AppKit
import Testing

@testable import ShatterBreak

/// Issue #67.
@Suite("OverlayManager freeze-frame reuse", .tags(.overlays))
@MainActor
struct OverlayManagerFreezeFrameTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2
    private let widescreen = CGSize(width: 160, height: 90)
    private let square = CGSize(width: 100, height: 100)

    @Test("a display that comes back is restored from the break's own capture")
    func returningDisplayReusesItsCapture() async throws {
        let capture = try TestImage.make(width: 160, height: 90)
        let context = try Context(capture: capture, displays: [primary])
        defer { context.manager.dismiss() }

        await context.startBreak()

        // The screen sleeps, dropping the display, then returns on wake.
        context.reconfigure(to: [])
        context.reconfigure(to: [primary])

        #expect(
            context.manager.overlayStates[primaryDisplay]?.backgroundImage === capture,
            """
            A returning display must be restored from the break's own capture; capturing \
            afresh would freeze the lock screen it came back through (issue #67).
            """
        )
        #expect(
            context.manager.captureTasks.count == 1,
            "Restoring from the retained capture must not start a second capture."
        )
    }

    @Test("a display connected mid-break takes a capture of its own")
    func newDisplayCapturesFresh() async throws {
        let capture = try TestImage.make(width: 160, height: 90)
        let context = try Context(capture: capture, displays: [primary])
        defer { context.manager.dismiss() }

        await context.startBreak()

        context.reconfigure(to: [primary, secondary])
        await context.settleCaptures()

        #expect(
            context.manager.captureTasks.count == 2,
            "Nothing is retained for a display that was never part of the break, so it captures."
        )
        #expect(context.manager.overlayStates[secondaryDisplay]?.backgroundImage === capture)
    }

    @Test("a display that changes shape re-fits the retained capture")
    func reframedDisplayRefitsItsCapture() async throws {
        let capture = try TestImage.make(width: 160, height: 90)
        let context = try Context(capture: capture, displays: [primary])
        defer { context.manager.dismiss() }

        await context.startBreak()
        #expect(context.manager.overlayStates[primaryDisplay]?.backgroundImage === capture)

        context.reconfigure(to: [StubScreens.display(primaryDisplay, size: square)])

        let fitted = try #require(context.manager.overlayStates[primaryDisplay]?.backgroundImage)
        #expect(
            fitted.width == 90 && fitted.height == 90,
            "A 16:9 capture on a square display is cropped square rather than squashed into it."
        )
    }

    @Test("repeated shape changes re-fit from the pristine capture")
    func repeatedReframesDoNotCompound() async throws {
        let capture = try TestImage.make(width: 160, height: 90)
        let context = try Context(capture: capture, displays: [primary])
        defer { context.manager.dismiss() }

        await context.startBreak()

        context.reconfigure(to: [StubScreens.display(primaryDisplay, size: square)])
        context.reconfigure(to: [primary])

        #expect(
            context.manager.overlayStates[primaryDisplay]?.backgroundImage === capture,
            """
            Every fit starts from the session's original capture, so returning to the \
            display's first shape restores the whole desktop rather than a crop of a crop.
            """
        )
    }

    // MARK: - Helpers

    private var primary: ScreenInfo { StubScreens.display(primaryDisplay, size: widescreen) }
    private var secondary: ScreenInfo {
        StubScreens.display(secondaryDisplay, x: widescreen.width, size: widescreen)
    }

    /// Both consents open, so the break shatters.
    @MainActor
    private struct Context {
        let manager: OverlayManager
        let screens: StubScreens

        private let environment = TestEnvironment()

        init(capture: CGImage, displays: [ScreenInfo]) throws {
            let screens = StubScreens(displays)
            self.screens = screens
            manager = environment.makeOverlayManager(
                screens: screens,
                capture: capture,
                directCaptureAccess: { .allowed }
            )
        }

        func startBreak() async {
            manager.show(environment.makeTimerState(), style: .animated)
            await settleCaptures()
        }

        func reconfigure(to displays: [ScreenInfo]) {
            screens.screens = displays
            manager.displaysDidChange()
        }

        func settleCaptures() async {
            for task in manager.captureTasks {
                await task.value
            }
        }
    }
}
