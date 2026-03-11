//
//  TimerStateOverlayTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import AppKit
import Testing

@testable import ShatterBreak

@MainActor
final class OverlaySpy: OverlayManaging {
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    func showOverlays(state: TimerState) { showCount += 1 }
    func dismissOverlays() { dismissCount += 1 }
}

@Suite("TimerState overlay behaviors", .serialized)
class TimerStateOverlayTests {
    private let savedWorkDuration: Double
    private let savedRestDuration: Double

    init() {
        // Save original UserDefaults values
        self.savedWorkDuration = UserDefaults.standard.double(forKey: "workDurationSecs")
        self.savedRestDuration = UserDefaults.standard.double(forKey: "restDurationSecs")

        // Clear for clean test setup
        UserDefaults.standard.removeObject(forKey: "workDurationSecs")
        UserDefaults.standard.removeObject(forKey: "restDurationSecs")
        UserDefaults.standard.set(WorkStartMode.automatic.rawValue, forKey: "workStartMode")
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
        UserDefaults.standard.removeObject(forKey: "workStartMode")
    }

    @Test("overlays show when entering rest and dismiss when leaving")
    @MainActor
    func overlaysShowAndDismiss() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(spy.showCount == 1)

        // Let rest finish and auto-start next work (user present)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        #expect(spy.dismissCount >= 1)
        #expect(state.isRunning)
        #expect(!state.isResting)
    }

    @Test("pause during rest skips rest and dismisses overlays")
    @MainActor
    func skipRestDismissesOverlay() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(spy.showCount == 1)
        state.pause()  // skip rest
        #expect(spy.dismissCount >= 1)
        #expect(state.isRunning, "Skip rest should start work")
        #expect(!state.isResting)
    }

    @Test("manual-start mode keeps overlay and waits for user action")
    @MainActor
    func manualOverlayPersists() async throws {
        UserDefaults.standard.set(WorkStartMode.manual.rawValue, forKey: "workStartMode")

        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000) // enter rest
        #expect(spy.showCount == 1)

        try await Task.sleep(nanoseconds: 1_300_000_000) // rest expires
        #expect(spy.dismissCount == 0, "Overlay should still be visible")
        #expect(state.awaitingReturn)

        // simulate user pressing the button
        state.start()
        #expect(spy.dismissCount >= 1)
    }
}
