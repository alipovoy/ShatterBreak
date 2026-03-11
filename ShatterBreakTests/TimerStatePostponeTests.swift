//
//  TimerStatePostponeTests.swift
//  ShatterBreakTests
//
//  Created by Alexey Lipovoy on 3/9/26.
//

import AppKit
import Testing

@testable import ShatterBreak

@Suite("TimerState postpone behaviors", .serialized)
class TimerStatePostponeTests {
    let postponeDurationSecs = 1.5
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

    @Test("canPostpone returns true when resting and not used this cycle")
    @MainActor
    func canPostponeTrueWhenRestingAndNotUsed() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(state.isResting)
        #expect(!state.hasPostponeBeenUsedThisCycle)

        #expect(state.canPostpone, "Should allow postpone when resting and not used")
    }

    @Test("canPostpone returns false when not resting")
    @MainActor
    func canPostponeFalseWhenNotResting() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        #expect(!state.isResting)
        #expect(!state.canPostpone, "Should not allow postpone when working")

        try await Task.sleep(nanoseconds: 1_300_000_000)  // finish work
        await Task.yield()
        #expect(state.isResting)

        state.postpone()
        #expect(!state.isResting)
        #expect(!state.canPostpone, "Should not allow postpone when in postponed work")
    }

    @Test("canPostpone returns false when already used this cycle")
    @MainActor
    func canPostponeFalseWhenAlreadyUsed() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(state.canPostpone)

        state.postpone()
        #expect(state.hasPostponeBeenUsedThisCycle)
        #expect(!state.canPostpone, "Should not allow multiple postpones per cycle")

        // Complete postponed work and return to rest
        try await Task.sleep(nanoseconds: 2_500_000_000)  // wait for postpone to expire
        await Task.yield()
        #expect(state.isResting)
        #expect(!state.canPostpone, "Should not allow postpone again in same rest cycle")
    }

    @Test("postpone() transitions state correctly and dismisses overlays")
    @MainActor
    func postponeTransitionsStateAndDismissesOverlays() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(state.isResting)
        #expect(spy.showCount == 1)

        state.postpone()
        #expect(state.isRunning && state.timeRemaining <= postponeDurationSecs, "Should be in postponed work state")
        #expect(state.hasPostponeBeenUsedThisCycle, "Should mark postpone as used")
        #expect(state.timeRemaining == postponeDurationSecs, "Should set correct postpone timer")
        #expect(spy.dismissCount == 1, "Should dismiss overlays when postponing")
    }

    @Test("postpone() does nothing if conditions not met")
    @MainActor
    func postponeDoesNothingIfConditionsNotMet() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        // Try to postpone when working
        state.start()
        #expect(!state.isResting)
        state.postpone()
        #expect(state.timeRemaining == 1, "Should not change time when postponing during work")

        // Enter rest and use postpone once
        try await Task.sleep(nanoseconds: 1_300_000_000)
        await Task.yield()
        #expect(state.isResting)

        state.postpone()
        #expect(state.isRunning && state.timeRemaining <= postponeDurationSecs)

        // Try to postpone again
        state.postpone()
        #expect(state.isRunning && state.timeRemaining <= postponeDurationSecs, "Should still be in postponed work (no change)")
        #expect(state.timeRemaining == postponeDurationSecs, "Time should remain unchanged")
    }

    @Test("postpone timer expires and resumes rest with correct time")
    @MainActor
    func postponeExpiresAndResumesRest() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(state.isResting)
        let originalRestTime = state.timeRemaining

        state.postpone()
        #expect(state.isRunning && state.timeRemaining <= postponeDurationSecs)

        // Wait for postpone to expire
        try await Task.sleep(nanoseconds: 2_500_000_000)
        await Task.yield()

        #expect(state.isResting, "Should resume rest after postpone expires")
        #expect(state.timeRemaining == originalRestTime, "Should resume with original rest time")
        #expect(spy.showCount == 2, "Should show overlays again when resuming rest")
    }

    @Test("hasPostponeBeenUsedThisCycle resets on new rest cycle")
    @MainActor
    func postponeFlagResetsOnNewCycle() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 1

        // First cycle
        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        state.postpone()
        #expect(state.hasPostponeBeenUsedThisCycle)

        // wait for postponed work to finish and resume rest
        while !state.isResting {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(state.hasPostponeBeenUsedThisCycle, "Flag should still be set during resumed rest")

        // wait for that rest to finish
        while state.isResting {
            try await Task.sleep(for: .milliseconds(100))
        }

        // now wait for second rest to start (new cycle)
        while !state.isResting {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(state.isResting, "Should have entered next rest")
        #expect(!state.hasPostponeBeenUsedThisCycle, "Flag should reset when entering new rest")
    }

    @Test("postpone during rest prevents multiple uses in same cycle")
    @MainActor
    func postponePreventsMultipleUsesInCycle() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        #expect(state.canPostpone)

        state.postpone()
        #expect(!state.canPostpone)

        // Complete postpone and resume rest
        try await Task.sleep(nanoseconds: 2_500_000_000)
        await Task.yield()
        #expect(state.isResting)
        #expect(!state.canPostpone, "Should not allow postpone again in same rest period")
    }

    @Test("pause during postponed work cancels postpone and starts fresh work")
    @MainActor
    func pauseDuringPostponedWork() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        state.postpone()

        #expect(!state.isResting)
        #expect(state.isRunning)

        // Pause during postponed work should skip rest and start new work
        state.pause()

        #expect(state.isRunning)
        #expect(!state.canPostpone, "Should have postpone flag set")
    }

    @Test("stop during postponed work clears all postpone state")
    @MainActor
    func stopDuringPostponedWork() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        state.postpone()

        #expect(state.hasPostponeBeenUsedThisCycle)

        // Stop should clear all state
        state.stop()

        #expect(!state.isRunning)
        #expect(!state.isResting)
        #expect(!state.hasPostponeBeenUsedThisCycle, "Stop should clear postpone flag")
        #expect(state.timeRemaining == 0)
    }

    @Test("early postpone preserves most of rest time")
    @MainActor
    func earlyPostponePreservesRestTime() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10  // long rest

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest

        let restTimeWhenPostponed = state.timeRemaining
        #expect(restTimeWhenPostponed > 9, "Should have ~9+ seconds of rest remaining")

        state.postpone()

        // Wait for postpone to expire and rest to resume
        try await Task.sleep(nanoseconds: 2_500_000_000)
        await Task.yield()

        #expect(state.isResting, "Postpone should expire")
        // Rest time should be nearly what we saved
        #expect(abs(state.timeRemaining - restTimeWhenPostponed) < 0.5, "Rest time should be preserved")
    }

    @Test("postpone near rest expiry resets rest timer appropriately")
    @MainActor
    func postponeNearRestExpiry() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 2  // short rest

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest (1.3s elapsed)
        try await Task.sleep(nanoseconds: 1_200_000_000)  // wait almost until rest expires (2.5s total, only 0.5s left)

        #expect(state.isResting)
        let remainingBeforePostpone = state.timeRemaining
        #expect(remainingBeforePostpone < 1, "Should have < 1 second remaining in rest")

        state.postpone()

        // wait for postpone to expire and rest to resume
        while !state.isResting {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(state.isResting, "Should resume rest after postpone")
        #expect(state.timeRemaining <= remainingBeforePostpone + 0.1, "Should have similar minimal time")
    }

    @Test("rest countdown continues accurately after postpone resumption")
    @MainActor
    func restCountdownAccuracyAfterResume() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 5

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        state.postpone()  // save rest time

        try await Task.sleep(nanoseconds: 2_100_000_000)  // wait for postpone to expire (1.5s) + margin
        await Task.yield()

        #expect(state.isResting, "Should have resumed rest after postpone expiry")
        let resumedRestTime = state.timeRemaining

        // Wait a known duration and verify countdown is accurate
        try await Task.sleep(nanoseconds: 1_200_000_000)  // wait ~1.2 seconds for countdown
        await Task.yield()

        let timeDifference = resumedRestTime - state.timeRemaining
        #expect(timeDifference >= 0.9 && timeDifference <= 1.5, "Rest should countdown by approximately 1 second")
    }

    @Test("system sleep during postponed work pauses postpone timer")
    @MainActor
    func systemSleepDuringPostpone() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: postponeDurationSecs)
        state.workDurationSecs = 1
        state.restDurationSecs = 10

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest
        state.postpone()

        let timeWhenSleep = state.timeRemaining
        #expect(timeWhenSleep <= postponeDurationSecs)

        // Simulate system sleep
        let nc = NSWorkspace.shared.notificationCenter
        nc.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(nanoseconds: 500_000_000)

        let timeWhenAsleep = state.timeRemaining

        // Wake system
        nc.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        await Task.yield()

        // Time should not have advanced significantly during sleep if timer was paused
        #expect(state.isResting || timeWhenAsleep >= timeWhenSleep - 0.1, "Timer should pause or resume rest during sleep")
    }

    @Test("savedRestRemaining correctly preserves rest duration")
    @MainActor
    func savedRestRemainingPreservation() async throws {
        let spy = OverlaySpy()
        let state = TimerState(overlayManager: spy, postponeDurationSecs: 1)  // very short postpone to test preservation
        state.workDurationSecs = 1
        state.restDurationSecs = 8

        state.start()
        try await Task.sleep(nanoseconds: 1_300_000_000)  // enter rest

        let timeBeforePostpone = state.timeRemaining
        state.postpone()

        // Verify rest time is restored after postpone
        try await Task.sleep(nanoseconds: 1_500_000_000)  // wait for short postpone
        await Task.yield()

        #expect(state.isResting, "Should have resumed rest")
        let restoredTime = state.timeRemaining

        // The restored time should be close to original (accounting for the timer tick)
        #expect(abs(restoredTime - timeBeforePostpone) < 0.2, "Saved rest time should be accurately restored")
    }
}
