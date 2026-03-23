import AppKit
import Testing

@testable import ShatterBreak

struct PermissionStatusCase: Sendable {
    let preflightAccess: Bool
    let hasLaunchedBefore: Bool
    let expectedStatus: ScreenCapturePermissionManager.Status
}

private final class ScreenCapturePermissionClientSpy {
    var preflightAccess = false
    private(set) var preflightCallCount = 0
    private(set) var requestCallCount = 0
    private(set) var openSettingsCallCount = 0

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
            openSystemSettings: { [unowned self] in
                openSettingsCallCount += 1
            }
        )
    }
}

@Suite("ScreenCapturePermissionManager")
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
        ),
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

        #expect(manager.status == testCase.expectedStatus)
        #expect(spy.preflightCallCount == 1)
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

        #expect(defaults.bool(forKey: launchKey))
        #expect(spy.requestCallCount == 1, "The first-launch request should only happen once.")
    }

    @Test("requestNow always requests permission")
    @MainActor
    func requestNowAlwaysRequestsPermission() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestNow()
        manager.requestNow()

        #expect(spy.requestCallCount == 2)
    }

    @Test("openSystemSettings delegates to the injected client")
    @MainActor
    func openSystemSettingsUsesClient() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.openSystemSettings()

        #expect(spy.openSettingsCallCount == 1)
    }

    @Test("becoming active refreshes permission status while unresolved")
    @MainActor
    func appDidBecomeActiveRefreshesStatusWhileUnresolved() {
        let environment = TestEnvironment()
        let defaults = environment.defaults
        defaults.set(true, forKey: launchKey)

        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.status == .denied)
        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(manager.status == .denied)
        #expect(spy.preflightCallCount == 2)
    }

    @Test("granted permission stops app-active observation")
    @MainActor
    func grantedStatusStopsObservingAppActive() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true

        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.status == .granted)
        #expect(spy.preflightCallCount == 1)

        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(manager.status == .granted)
        #expect(spy.preflightCallCount == 1)
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
        #expect(weakManager == nil)
    }
}
