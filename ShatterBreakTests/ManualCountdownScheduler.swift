import Foundation

@testable import ShatterBreak

/// A `CountdownScheduler` that drives time manually so tests stay fast and
/// deterministic. `advance` simulates one tick (time moves, expiry is re-evaluated);
/// `elapse` moves time without re-evaluating, mirroring elapsed time observed before
/// the next tick.
///
/// Delivery is one-shot, matching `SystemCountdownScheduler`: each `scheduleExpiry`
/// owes exactly one callback, and whatever wants another has to ask. Retaining the
/// callback across ticks instead would have made this fake re-fire a shot production
/// had already spent, hiding every way a countdown can lose its only expiry.
///
/// `cancelExpiry` is instantaneous here and is not in production, where the callback
/// runs one statement after `try Task.checkCancellation()` succeeds. A cancel landing
/// in that gap still delivers, which `fireExpiryIgnoringCancellation` reproduces.
@MainActor
final class ManualCountdownScheduler: CountdownScheduler {
    private var onExpiry: (@MainActor @Sendable () -> Void)?
    /// The last callback scheduled, deliberately outliving `cancelExpiry`.
    private var lastScheduled: (@MainActor @Sendable () -> Void)?

    var now: Date

    nonisolated init(now: Date = .init(timeIntervalSince1970: 0)) {
        self.now = now
    }

    func scheduleExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onExpiry = onExpiry
        self.lastScheduled = onExpiry
    }

    func cancelExpiry() {
        onExpiry = nil
    }

    func advance(by interval: TimeInterval = 1) {
        now = now.addingTimeInterval(interval)
        fireExpiry()
    }

    /// Delivers the pending expiry without moving time.
    ///
    /// Reproduces the production shape where the scheduler's monotonic wait elapses
    /// before the wall clock reaches the deadline, so the callback arrives with time
    /// still on the countdown.
    func fireExpiryEarly() {
        fireExpiry()
    }

    /// Delivers the last scheduled callback even after `cancelExpiry`.
    ///
    /// The one production delivery a cancellation cannot stop: `SystemCountdownScheduler`
    /// checks cancellation and then invokes the callback, so a cancel arriving between
    /// those two statements still fires.
    func fireExpiryIgnoringCancellation() {
        lastScheduled?()
    }

    private func fireExpiry() {
        let pending = onExpiry
        onExpiry = nil
        pending?()
    }

    func elapse(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
