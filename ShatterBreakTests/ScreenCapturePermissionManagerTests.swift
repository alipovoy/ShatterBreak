//
//  ScreenCapturePermissionManagerTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import Foundation
import Testing

@testable import ShatterBreak

@Suite("ScreenCapturePermissionManager")
class ScreenCapturePermissionManagerTests {
    private let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private let environment = TestEnvironment()
    private var defaults: UserDefaults { environment.defaults }

    @Test("requestIfFirstLaunch sets launch key on first call")
    @MainActor
    func firstLaunchSetsKey() async throws {
        defaults.removeObject(forKey: launchKey)
        #expect(!defaults.bool(forKey: launchKey))

        let manager = environment.makePermissionManager()
        _ = manager  // silence unused

        // Ensure main-actor init work has run
        await Task.yield()

        #expect(!defaults.bool(forKey: launchKey), "Init should not set hasLaunchedBefore")

        manager.requestIfFirstLaunch()
        await Task.yield()

        #expect(defaults.bool(forKey: launchKey), "requestIfFirstLaunch should set hasLaunchedBefore")
    }
}
