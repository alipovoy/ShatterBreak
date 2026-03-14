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

@Suite("TimerState overlay behaviors")
class TimerStateOverlayTests {
    private let environment = TestEnvironment()
    private var defaults: UserDefaults { environment.defaults }

    @Test("overlays show when entering rest and dismiss when leaving")
    @MainActor
    func overlaysShowAndDismiss() async throws {
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(for: .seconds(1.3))  // enter rest
        #expect(spy.showCount == 1)

        // Let rest finish and auto-start next work (user present)
        try await Task.sleep(for: .seconds(1.3))
        #expect(spy.dismissCount >= 1)
        #expect(state.isRunning)
        #expect(!state.isResting)
    }

    @Test("pause during rest skips rest and dismisses overlays")
    @MainActor
    func skipRestDismissesOverlay() async throws {
        defaults.set(WorkStartMode.automatic.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(for: .seconds(1.3))  // enter rest
        #expect(spy.showCount == 1)
        state.pause()  // skip rest
        #expect(spy.dismissCount >= 1)
        #expect(state.isRunning, "Skip rest should start work")
        #expect(!state.isResting)
    }

    @Test("manual-start mode keeps overlay and waits for user action")
    @MainActor
    func manualOverlayPersists() async throws {
        defaults.set(WorkStartMode.manual.rawValue, forKey: PreferenceKeys.workStartMode)

        let spy = OverlaySpy()
        let state = environment.makeTimerState(overlayManager: spy)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(for: .seconds(1.3)) // enter rest
        #expect(spy.showCount == 1)

        try await Task.sleep(for: .seconds(1.3)) // rest expires
        #expect(spy.dismissCount == 0, "Overlay should still be visible")
        #expect(state.awaitingReturn)

        // simulate user pressing the button
        state.start()
        #expect(spy.dismissCount >= 1)
    }
}
