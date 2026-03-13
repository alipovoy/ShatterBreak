//
//  ScreenCapturePermissionManagerTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import Foundation
import Testing

@testable import ShatterBreak

@Suite("ScreenCapturePermissionManager", .serialized)
class ScreenCapturePermissionManagerTests {
    private let savedLaunchKey: Bool
    private let launchKey = "com.shatterbreak.hasLaunchedBefore"

    init() {
        self.savedLaunchKey = UserDefaults.standard.bool(forKey: launchKey)
        UserDefaults.standard.removeObject(forKey: launchKey)
    }

    deinit {
        if savedLaunchKey {
            UserDefaults.standard.set(true, forKey: launchKey)
        } else {
            UserDefaults.standard.removeObject(forKey: launchKey)
        }
    }

    @Test("requestIfFirstLaunch sets launch key on first call")
    @MainActor
    func firstLaunchSetsKey() async throws {
        let defaults = UserDefaults.standard

        defaults.removeObject(forKey: launchKey)
        #expect(!defaults.bool(forKey: launchKey))

        let manager = ScreenCapturePermissionManager()
        _ = manager  // silence unused

        // Ensure main-actor init work has run
        await Task.yield()

        #expect(!defaults.bool(forKey: launchKey), "Init should not set hasLaunchedBefore")

        manager.requestIfFirstLaunch()
        await Task.yield()

        #expect(defaults.bool(forKey: launchKey), "requestIfFirstLaunch should set hasLaunchedBefore")
    }
}

