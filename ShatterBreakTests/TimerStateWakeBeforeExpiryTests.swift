//
//  TimerStateWakeBeforeExpiryTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState wake before rest expiry", .serialized)
class TimerStateWakeBeforeExpiryTests {
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

    @Test("wake during rest before expiry keeps overlay and rest")
    @MainActor
    func wakeDuringRestBeforeExpiryKeepsState() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // entered rest
        #expect(state.isResting)
        #expect(spy.showCount == 1)

        let nc = NSWorkspace.shared.notificationCenter
        nc.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 500_000_000)  // not enough to expire rest
        nc.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(state.isResting, "Rest should continue if not expired")
        #expect(spy.dismissCount == 0, "Overlay should remain until rest ends")
    }
}
