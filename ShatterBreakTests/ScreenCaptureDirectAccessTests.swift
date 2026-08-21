import Testing

@testable import ShatterBreak

/// Covers macOS 15+'s direct-capture confirmation — the consent that sits on top of
/// Screen Recording and used to be discovered mid-break (issue #90).
@Suite("ScreenCapturePermissionManager direct capture", .tags(.permissions))
struct ScreenCaptureDirectAccessTests {
    private let launchKey = "com.shatterbreak.hasLaunchedBefore"

    @Test("preparing for capture confirms direct capture when Screen Recording is granted")
    @MainActor
    func prepareForCaptureConfirmsDirectCapture() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(
            manager.directCaptureAccess == .unknown,
            "Direct capture starts unknown so a break before the first probe still shatters."
        )

        await manager.prepareForCapture()

        #expect(spy.confirmDirectCaptureCallCount == 1, "Preparing should probe the direct-capture consent once.")
        #expect(manager.directCaptureAccess == .allowed, "A successful probe should record allowed access.")
    }

    @Test("a declined direct-capture probe is recorded as refused")
    @MainActor
    func refusedDirectCaptureIsRecorded() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        spy.directCaptureAllowed = false
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        await manager.prepareForCapture()

        #expect(manager.directCaptureAccess == .refused, "A failed probe should record the refusal for the UI.")
    }

    @Test("a refusal is not re-probed on later work sessions")
    @MainActor
    func refusalIsNotReprobed() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        spy.directCaptureAllowed = false
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        await manager.prepareForCapture()
        await manager.prepareForCapture()

        #expect(
            spy.confirmDirectCaptureCallCount == 1,
            "Re-raising the system dialog every work session would turn a monthly ask into a nag."
        )
    }

    @Test("the user can re-open the direct-capture dialog after refusing it")
    @MainActor
    func userCanRetryAfterRefusal() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        spy.directCaptureAllowed = false
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        await manager.prepareForCapture()
        spy.directCaptureAllowed = true
        await manager.confirmDirectCaptureAccess()

        #expect(spy.confirmDirectCaptureCallCount == 2, "An explicit retry should probe again despite the refusal.")
        #expect(manager.directCaptureAccess == .allowed, "Allowing on the retry should clear the refusal.")
    }

    @Test("direct capture is not probed while Screen Recording is missing")
    @MainActor
    func directCaptureIsNotProbedWithoutScreenRecording() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = false
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        await manager.prepareForCapture()

        #expect(
            spy.confirmDirectCaptureCallCount == 0,
            "Without Screen Recording the probe would fail for an unrelated reason and mislabel the result."
        )
        #expect(manager.directCaptureAccess == .unknown, "An unattempted probe must leave the consent unknown.")
    }

    @Test("preparing for capture makes the first-launch request")
    @MainActor
    func prepareForCaptureRequestsOnFirstLaunch() async {
        let environment = TestEnvironment()
        environment.defaults.removeObject(forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        await manager.prepareForCapture()

        #expect(
            spy.requestCallCount == 1,
            """
            Starting work must be able to raise the first-launch prompt: the menu content \
            that used to own it is built lazily and may never appear (issue #90).
            """
        )
    }

    @Test("a refusal survives relaunch, so the monthly ask is not raised every launch")
    @MainActor
    func refusalIsRemembered() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        spy.directCaptureAllowed = false

        let firstLaunch = environment.makePermissionManager(permissionClient: spy.client)
        await firstLaunch.prepareForCapture()
        #expect(firstLaunch.directCaptureAccess == .refused)

        // A second manager over the same store stands in for the next launch.
        let nextLaunch = environment.makePermissionManager(permissionClient: spy.client)
        #expect(nextLaunch.directCaptureAccess == .refused, "The decline should be restored from the store.")

        await nextLaunch.prepareForCapture()

        #expect(
            spy.confirmDirectCaptureCallCount == 1,
            """
            A login-item menu bar app relaunches constantly; re-probing would put the \
            system dialog on screen at every boot.
            """
        )
    }

    @Test("allowing direct capture clears a remembered decline")
    @MainActor
    func allowingClearsTheRememberedDecline() async {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true
        spy.directCaptureAllowed = false

        let manager = environment.makePermissionManager(permissionClient: spy.client)
        await manager.prepareForCapture()

        spy.directCaptureAllowed = true
        await manager.confirmDirectCaptureAccess()

        let nextLaunch = environment.makePermissionManager(permissionClient: spy.client)
        #expect(nextLaunch.directCaptureAccess == .unknown, "A later allow should not leave a stale decline stored.")
    }
}
