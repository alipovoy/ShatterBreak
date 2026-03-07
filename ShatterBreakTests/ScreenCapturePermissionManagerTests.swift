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
struct ScreenCapturePermissionManagerTests {

    @Test("first launch sets launch key")
    @MainActor
    func firstLaunchSetsKey() async throws {
        let defaults = UserDefaults.standard
        let launchKey = "com.shatterbreak.hasLaunchedBefore"

        defaults.removeObject(forKey: launchKey)
        #expect(!defaults.bool(forKey: launchKey))

        let manager = ScreenCapturePermissionManager()
        _ = manager  // silence unused

        // Ensure main-actor init work has run
        await Task.yield()

        #expect(defaults.bool(forKey: launchKey), "First init should set hasLaunchedBefore")
    }
}
