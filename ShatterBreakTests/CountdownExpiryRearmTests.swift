import Testing

@testable import ShatterBreak

/// The countdown must never lose its only expiry callback.
///
/// `SystemCountdownScheduler` owes exactly one callback per `scheduleExpiry`, and it
/// waits on `Task.sleep`'s monotonic clock while the deadline lives on the wall clock.
/// When the callback arrives early — the clocks need only differ by a fraction of a
/// second — spending it on a caller that sees time remaining would leave nothing armed,
/// and the timer would sit at 00:00 dropping every transition after it.
@Suite("Countdown expiry re-arming", .tags(.timerState), .timeLimit(.minutes(1)))
struct CountdownExpiryRearmTests {
    @Test("an early callback re-arms instead of expiring the countdown")
    @MainActor
    func earlyCallbackRearms() async {
        let scheduler = ManualCountdownScheduler()
        let countdown = Countdown(scheduler: scheduler)
        var expiries = 0

        countdown.begin(for: 10) { expiries += 1 }

        scheduler.fireExpiryEarly()
        #expect(expiries == 0, "A callback arriving with time left must not expire the countdown.")

        // The re-armed callback is the whole point: without it the one shot is spent and
        // the deadline passes unobserved.
        scheduler.advance(by: 10)
        #expect(expiries == 1, "The re-armed callback must fire once the deadline is reached.")
    }

    @Test("repeated early callbacks still expire exactly once at the deadline")
    @MainActor
    func repeatedEarlyCallbacksExpireOnce() async {
        let scheduler = ManualCountdownScheduler()
        let countdown = Countdown(scheduler: scheduler)
        var expiries = 0

        countdown.begin(for: 3) { expiries += 1 }

        for _ in 0..<5 {
            scheduler.fireExpiryEarly()
        }
        #expect(expiries == 0, "No number of early callbacks should expire the countdown.")

        scheduler.advance(by: 3)
        #expect(expiries == 1, "The countdown should expire exactly once, at its deadline.")
    }

    @Test("a callback that outlives a freeze neither expires nor re-arms")
    @MainActor
    func frozenCountdownIgnoresStaleCallback() async {
        let scheduler = ManualCountdownScheduler()
        let countdown = Countdown(scheduler: scheduler)
        var expiries = 0

        countdown.begin(for: 10) { expiries += 1 }
        countdown.freeze()

        // The delivery a cancellation cannot stop, which is the only one this guard is
        // there for. Re-arming here would put a live expiry behind a paused timer; the
        // frozen remainder resumes through `begin` instead.
        scheduler.fireExpiryIgnoringCancellation()
        #expect(expiries == 0, "A frozen countdown owes no expiry.")
        #expect(countdown.remaining(at: scheduler.now) == 10, "The freeze should keep the remainder.")

        scheduler.advance(by: 20)
        #expect(expiries == 0, "The stale callback must not have re-armed behind the freeze.")
    }

    @Test("a callback that outlives a clear does not expire")
    @MainActor
    func clearedCountdownIgnoresStaleCallback() async {
        let scheduler = ManualCountdownScheduler()
        let countdown = Countdown(scheduler: scheduler)
        var expiries = 0

        countdown.begin(for: 10) { expiries += 1 }
        countdown.clear()

        scheduler.fireExpiryIgnoringCancellation()
        #expect(expiries == 0, "A cleared countdown owes no expiry.")

        scheduler.advance(by: 20)
        #expect(expiries == 0, "The stale callback must not have re-armed after the clear.")
    }

    @Test("work still transitions to rest after an early expiry callback")
    @MainActor
    func workTransitionsToRestAfterEarlyCallback() async {
        let environment = TestEnvironment()
        let state = environment.makeTimerState()
        state.workDurationSecs = 5
        state.restDurationSecs = 3

        state.start()

        // The shape of the live bug: the callback lands just short of the deadline, with
        // no sleep involved, so `stalledTransition` would never see it either.
        environment.fireExpiryEarly()
        #expect(state.mode == .running, "An early callback must not transition the timer.")

        await environment.advanceTime(by: 5)
        #expect(state.isResting, "The work session must still hand over to the break.")
        #expect(state.sleptAt == nil, "No sleep was involved in this stall.")
    }
}
