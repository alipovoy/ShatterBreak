//
//  TimerStateTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/6/26.
//

import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState basic flows", .serialized)
class TimerStateBasicTests {
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

    @Test("start() initializes and transitions to rest")
    @MainActor
    func startTransitionsToRest() async throws {
        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 2

        state.start()
        #expect(state.isRunning)
        #expect(!state.isPaused)
        #expect(!state.isResting)
        #expect(state.timeRemaining == 1)

        try await Task.sleep(nanoseconds: 1_200_000_000)
        await Task.yield()

        #expect(state.isResting, "Should enter rest after work completes")
        #expect(state.isRunning, "Work timer transitions directly into rest with timer running")
        #expect(
            state.timeRemaining == 2, "On rest start, timeRemaining should reset to rest duration")
    }

    @Test("pause during work freezes countdown; resume continues")
    @MainActor
    func pauseAndResume() async throws {
        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        state.pause()
        let snapshot = state.timeRemaining

        #expect(state.isPaused)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        #expect(state.timeRemaining == snapshot, "timeRemaining should not change while paused")

        state.resume()
        try await Task.sleep(nanoseconds: 1_200_000_000)

        #expect(state.timeRemaining < snapshot, "timeRemaining should resume decreasing")
    }

    @Test("stop() cancels and resets state")
    @MainActor
    func stopResets() async throws {
        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 5
        state.restDurationSecs = 2

        state.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        state.stop()

        #expect(!state.isRunning)
        #expect(!state.isPaused)
        #expect(!state.isResting)
        #expect(state.timeRemaining == 0)
    }
}

@Suite("TimerState sleep/wake behaviors", .serialized)
class TimerStateSleepWakeTests {
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

    @Test("display sleep auto-pauses work; wake auto-resumes")
    @MainActor
    func displaySleepAutoPauseAndResume() async throws {
        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 3
        state.restDurationSecs = 2

        state.start()
        try await Task.sleep(nanoseconds: 800_000_000)
        let nc = NSWorkspace.shared.notificationCenter

        nc.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        await Task.yield()
        #expect(state.isPaused, "Work should auto-pause on display sleep")

        nc.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 400_000_000)
        await Task.yield()
        #expect(!state.isPaused, "Work should auto-resume on display wake")

        try await Task.sleep(nanoseconds: 3_000_000_000)
        await Task.yield()
        #expect(state.isResting, "Should still transition to rest after resume")
    }

    @Test("rest expires while system is asleep → returns to idle on wake (R2)")
    @MainActor
    func restExpiresWhileAwayReturnsIdle() async throws {
        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        await Task.yield()
        #expect(state.isResting)

        let nc = NSWorkspace.shared.notificationCenter

        nc.post(name: NSWorkspace.willSleepNotification, object: nil)

        try await Task.sleep(nanoseconds: 1_500_000_000)

        nc.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        await Task.yield()

        #expect(!state.isRunning, "After R2, app should be idle")
        #expect(!state.isResting, "Rest should be cleared after wake when expired")
    }
}
