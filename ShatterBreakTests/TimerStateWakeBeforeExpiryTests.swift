//
//  TimerStateWakeBeforeExpiryTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState wake before rest expiry")
class TimerStateWakeBeforeExpiryTests {
    private let environment = TestEnvironment()
    private var defaults: UserDefaults { environment.defaults }

    @Test("wake during rest before expiry keeps overlay and rest")
    @MainActor
    func wakeDuringRestBeforeExpiryKeepsState() async throws {
        defaults.set(WorkStartMode.automatic.rawValue, forKey: "workStartMode")

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        try await Task.sleep(for: .seconds(1.3))  // entered rest
        #expect(state.isResting)
        #expect(spy.showCount == 1)

        let nc = environment.workspaceNotificationCenter
        nc.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(for: .seconds(0.5))  // not enough to expire rest
        nc.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .seconds(0.2))

        #expect(state.isResting, "Rest should continue if not expired")
        #expect(spy.dismissCount == 0, "Overlay should remain until rest ends")
    }
}
