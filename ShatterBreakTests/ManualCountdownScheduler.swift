import Foundation

@testable import ShatterBreak

/// A `CountdownScheduler` that drives time manually so tests stay fast and
/// deterministic. `advance` simulates one tick (time moves, expiry is re-evaluated);
/// `elapse` moves time without re-evaluating, mirroring elapsed time observed before
/// the next tick.
@MainActor
final class ManualCountdownScheduler: CountdownScheduler {
    private var onExpiry: (@MainActor @Sendable () -> Void)?

    var now: Date

    nonisolated init(now: Date = .init(timeIntervalSince1970: 0)) {
        self.now = now
    }

    func scheduleExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onExpiry = onExpiry
    }

    func cancelExpiry() {
        onExpiry = nil
    }

    func advance(by interval: TimeInterval = 1) {
        now = now.addingTimeInterval(interval)
        onExpiry?()
    }

    func elapse(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
