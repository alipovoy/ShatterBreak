import AppKit
import Testing

@testable import ShatterBreak

struct PermissionStatusCase: Sendable {
    let preflightAccess: Bool
    let hasLaunchedBefore: Bool
    let expectedStatus: ScreenCapturePermissionManager.Status
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

    @Test("requesting access marks the store and asks once per launch")
    @MainActor
    func requestAccessAsksOncePerLaunch() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.removeObject(forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestAccessIfNeeded()
        manager.requestAccessIfNeeded()

        #expect(defaults.bool(forKey: launchKey), "Requesting access should persist the marker the UI reads.")
        #expect(spy.requestCallCount == 1, "A launch should raise at most one request.")
    }

    @Test("a previously requested but ungranted permission is requested again next launch")
    @MainActor
    func requestAccessRetriesOnALaterLaunch() {
        let environment = TestEnvironment()
        environment.defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestAccessIfNeeded()

        #expect(
            spy.requestCallCount == 1,
            """
            The grant is keyed to the code-signing identity, so an ad-hoc rebuild leaves \
            TCC with no record; a permanent flag meant the app never asked again (#43). \
            macOS suppresses the dialog when it already holds an answer.
            """
        )
    }

    @Test("granted permission is never re-requested")
    @MainActor
    func grantedAccessIsNotRequested() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true

        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestAccessIfNeeded()

        #expect(spy.requestCallCount == 0, "There is nothing to ask for once access is granted.")
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
