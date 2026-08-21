import AppKit
import Testing

@testable import ShatterBreak

@Suite("ScreenCapturePermissionManager", .tags(.permissions))
struct ScreenCapturePermissionManagerTests {
    @Test("access reflects preflight, whether or not the app has ever asked")
    @MainActor
    func accessReflectsPreflight() {
        let environment = TestEnvironment()

        let denied = ScreenCapturePermissionClientSpy()
        #expect(
            environment.makePermissionManager(permissionClient: denied.client)
                .hasScreenRecordingAccess == false,
            """
            Never-asked and denied are the same answer to "can Shatter capture", and \
            must look the same to the UI — a warning hidden until the first request \
            reads as a broken warning (issue #90).
            """
        )
        #expect(denied.preflightCallCount == 1, "Permission refresh should preflight exactly once.")

        let granted = ScreenCapturePermissionClientSpy()
        granted.preflightAccess = true
        #expect(environment.makePermissionManager(permissionClient: granted.client).hasScreenRecordingAccess)
    }

    @Test("access is requested at most once per launch")
    @MainActor
    func requestAccessAsksOncePerLaunch() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        manager.requestAccessIfNeeded()
        manager.requestAccessIfNeeded()

        #expect(spy.requestCallCount == 1, "A launch should raise at most one request.")
    }

    @Test("a later launch asks again while permission is still missing")
    @MainActor
    func requestAccessRetriesOnALaterLaunch() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()

        environment.makePermissionManager(permissionClient: spy.client).requestAccessIfNeeded()
        environment.makePermissionManager(permissionClient: spy.client).requestAccessIfNeeded()

        #expect(
            spy.requestCallCount == 2,
            """
            The grant is keyed to the code-signing identity, so an ad-hoc rebuild leaves \
            TCC with no record; a persisted flag meant the app never asked again (#43). \
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

    @Test("becoming active refreshes access while it is still missing")
    @MainActor
    func appDidBecomeActiveRefreshesAccessWhileUnresolved() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.hasScreenRecordingAccess == false, "An app without permission should start without access.")
        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(
            manager.hasScreenRecordingAccess == false,
            "Becoming active should keep access off while preflight still fails."
        )
        #expect(spy.preflightCallCount == 2, "Unresolved permission should refresh when the app becomes active.")
    }

    @Test("granted permission stops app-active observation")
    @MainActor
    func grantedAccessStopsObservingAppActive() {
        let environment = TestEnvironment()
        let spy = ScreenCapturePermissionClientSpy()
        spy.preflightAccess = true

        let manager = environment.makePermissionManager(permissionClient: spy.client)

        #expect(manager.hasScreenRecordingAccess, "Granted preflight should report access.")
        #expect(spy.preflightCallCount == 1, "Initial permission setup should preflight once.")

        environment.appNotificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(manager.hasScreenRecordingAccess, "Access should remain granted after app activation.")
        #expect(spy.preflightCallCount == 1, "Granted access should stop further app-active refreshes.")
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
