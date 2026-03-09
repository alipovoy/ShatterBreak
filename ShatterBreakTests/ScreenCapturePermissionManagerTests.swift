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
    private let savedWorkDuration: Double
    private let savedRestDuration: Double

    init() {
        // Save original UserDefaults values
        self.savedWorkDuration = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.savedRestDuration = UserDefaults.standard.double(forKey: "restDurationSecs")

        // Clear for clean test setup
        UserDefaults.standard.removeObject(forKey: "workDurationSecs")
        UserDefaults.standard.removeObject(forKey: "restDurationSecs")
    }

    deinit {
        // Restore original UserDefaults values
        if savedWorkDuration > 0 {
            UserDefaults.standard.set(savedWorkDuration, forKey: "workDurationSecs")
        } else {
            UserDefaults.standard.removeObject(forKey: "workDurationSecs")
        }

        if savedRestDuration > 0 {
            UserDefaults.standard.set(savedRestDuration, forKey: "restDurationSecs")
        } else {
            UserDefaults.standard.removeObject(forKey: "restDurationSecs")
        }
    }

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
