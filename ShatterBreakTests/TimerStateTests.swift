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
        // Ensure automatic mode (default) so behaviour is predictable.
        UserDefaults.standard.set(WorkStartMode.automatic.rawValue, forKey: "workStartMode")

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
        #expect(state.isRunning)
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
        #expect(state.timeRemaining == 0)
    }

    @Test("manual mode waits for user after rest expiry")
    @MainActor
    func manualModeDelaysWorkStart() async throws {
        UserDefaults.standard.set(WorkStartMode.manual.rawValue, forKey: "workStartMode")

        let state = TimerState(overlayManager: OverlaySpy())
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        state.start()
        try await Task.sleep(nanoseconds: 1_200_000_000) // enter rest
        #expect(state.isResting)

        try await Task.sleep(nanoseconds: 1_200_000_000) // rest should expire
        await Task.yield()

        #expect(!state.isRunning, "Work should not auto-start in manual mode")
        #expect(state.awaitingReturn)
        #expect(state.timeRemaining == 0)

        // simulate user hitting the button
        state.start()
        #expect(state.isRunning)
        #expect(!state.awaitingReturn)
    }

    // MARK: - Formatting helpers

    @Test("formatting helper produces zero-padded strings")
    @MainActor
    func formattingProducesCorrectOutput() {
        #expect(TimerState.format(timeInterval: 0) == "00:00")
        #expect(TimerState.format(timeInterval: 5) == "00:05")
        #expect(TimerState.format(timeInterval: 65) == "01:05")
        #expect(TimerState.format(timeInterval: 599) == "09:59")
        #expect(TimerState.format(timeInterval: 600) == "10:00")
    }

    @Test("visibility flag reflects running vs resting")
    @MainActor
    func visibilityFlagRespectsState() {
        let state = TimerState(overlayManager: OverlaySpy())

        // make sure awaitingReturn suppresses indicator
        state.mode = .awaitingReturn
        #expect(!state.shouldShowTimeInMenuBar)

        state.mode = .idle

        // idle
        #expect(!state.shouldShowTimeInMenuBar)

        // running work
        state.mode = .running
        #expect(state.shouldShowTimeInMenuBar)

        // paused during work
        state.mode = .paused
        #expect(state.shouldShowTimeInMenuBar)

        // resting, regardless of running/paused
        state.mode = .resting
        #expect(!state.shouldShowTimeInMenuBar)
    }

    @Test("formattedTimeRemaining still produces string regardless of state")
    @MainActor
    func formattingUnaffectedByState() {
        let state = TimerState(overlayManager: OverlaySpy())
        state.timeRemaining = 75
        #expect(state.formattedTimeRemaining == "01:15")

        // state changes shouldn't mutate formatted text
        state.mode = .running
        state.mode = .resting
        #expect(state.formattedTimeRemaining == "01:15")
    }

    @Test("app storage key toggles correctly")
    @MainActor
    func appStorageKeyBehavior() {
        let key = "showTimerInMenuBar"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(!UserDefaults.standard.bool(forKey: key))
        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key))
    }

    @Test("work start mode default and storage")
    @MainActor
    func workStartModeStorage() {
        let key = "workStartMode"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
        // default computed property should treat nil as automatic
        #expect(WorkStartMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .automatic == .automatic)
        UserDefaults.standard.set(WorkStartMode.manual.rawValue, forKey: key)
        #expect(WorkStartMode(rawValue: UserDefaults.standard.string(forKey: key)!) == .manual)
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
