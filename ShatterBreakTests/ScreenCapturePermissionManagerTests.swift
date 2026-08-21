import AppKit
import Testing

@testable import ShatterBreak

struct PermissionStatusCase: Sendable {
    let preflightAccess: Bool
    let hasLaunchedBefore: Bool
    let expectedStatus: ScreenCapturePermissionManager.Status
}

@MainActor
private final class ScreenCapturePermissionClientSpy {
    var preflightAccess = false
    var directCaptureAllowed = true
    private(set) var preflightCallCount = 0
    private(set) var requestCallCount = 0
    private(set) var openSettingsCallCount = 0
    private(set) var confirmDirectCaptureCallCount = 0

    var client: ScreenCapturePermissionClient {
        ScreenCapturePermissionClient(
            preflightAccess: { [unowned self] in
                preflightCallCount += 1
                return preflightAccess
            },
            requestAccess: { [unowned self] in
                requestCallCount += 1
                return preflightAccess
            },
            confirmDirectCaptureAccess: { [unowned self] in
                confirmDirectCaptureCallCount += 1
                return directCaptureAllowed
            },
            openSystemSettings: { [unowned self] in
                openSettingsCallCount += 1
            }
        )
    }
}

@Suite("ScreenCapturePermissionManager", .tags(.permissions))
struct ScreenCapturePermissionManagerTests {
    private let launchKey = "com.shatterbreak.hasLaunchedBefore"

    @Test(arguments: [
        PermissionStatusCase(
            preflightAccess: true,
            hasLaunchedBefore: false,
            expectedStatus: .granted
        ),
        PermissionStatusCase(
            preflightAccess: false,
            hasLaunchedBefore: false,
            expectedStatus: .notDetermined
        ),
        PermissionStatusCase(
            preflightAccess: false,
            hasLaunchedBefore: true,
            expectedStatus: .denied
        )
    ])
    @MainActor
    func refreshSetsExpectedStatus(_ testCase: PermissionStatusCase) {
        let environment = TestEnvironment()
        let defaults = environment.defaults

        if testCase.hasLaunchedBefore {
            defaults.set(true, forKey: launchKey)
        } else {
            defaults.removeObject(forKey: launchKey)
        }

        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = testCase.preflightAccess

        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(
            manager.status == testCase.expectedStatus,
            "Refresh should derive the expected permission status from preflight and launch state."
        )
        #expect(spy.preflightCallCount == 1, "Permission refresh should preflight exactly once.")
    }

    @Test("requestIfFirstLaunch sets the launch key and requests once")
    @MainActor
    func requestIfFirstLaunchRequestsOnce() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.removeObject(forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestIfFirstLaunch()
        manager.requestIfFirstLaunch()

        #expect(defaults.bool(forKey: launchKey), "First-launch request should persist the launch marker.")
        #expect(spy.requestCallCount == 1, "The first-launch request should only happen once.")
    }

    @Test("openSystemSettings delegates to the injected client")
    @MainActor
    func openSystemSettingsUsesClient() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.openSystemSettings()

        #expect(spy.openSettingsCallCount == 1, "Opening system settings should delegate to the permission client.")
    }

    @Test("becoming active refreshes permission status while unresolved")
    @MainActor
    func appDidBecomeActiveRefreshesStatusWhileUnresolved() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.status == .denied, "A previously launched app without permission should start denied.")
        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(manager.status == .denied, "Becoming active should keep denied status when preflight still fails.")
        #expect(spy.preflightCallCount == 2, "Unresolved permission should refresh when the app becomes active.")
    }

    @Test("granted permission stops app-active observation")
    @MainActor
    func grantedStatusStopsObservingAppActive() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true

        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.status == .granted, "Granted preflight should set granted status.")
        #expect(spy.preflightCallCount == 1, "Initial permission setup should preflight once.")

        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(manager.status == .granted, "Granted status should remain granted after app activation.")
        #expect(spy.preflightCallCount == 1, "Granted status should stop further app-active refreshes.")
    }

    // MARK: - Direct capture consent (issue #90)

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

    @Test("manager deallocates while the app-active observer is registered")
    @MainActor
    func managerDeallocatesWhileObserving() async {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        weak var weakManager: ScreenCapturePermissionManager?

        do {
            let manager = environment.makePermissionManager(permissionClient: spy.client)
            weakManager = manager
            await Task.yield()
        }

        await Task.yield()
        #expect(weakManager == nil, "Permission manager should deallocate while observing app-active notifications.")
    }
}
