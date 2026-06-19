import Foundation

/// Supplies the current time and schedules a single one-shot expiry callback for a
/// `Countdown`.
///
/// Injecting this is the one test seam for time: the production implementation reads
/// the wall clock and schedules expiry with `Task.sleep`, while tests provide a fake
/// that advances time on demand. Both share a single code path through `Countdown`,
/// so there is no production/test behavior fork.
@MainActor
protocol CountdownScheduler: AnyObject {
    /// The current moment, used to derive the remaining time.
    var now: Date { get }

    /// Schedules `onExpiry` to run after `delay` seconds, replacing any pending expiry.
    func scheduleExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    )

    /// Cancels a pending expiry, if any.
    func cancelExpiry()
}

/// The production scheduler: reads the wall clock and fires expiry via `Task.sleep`.
@MainActor
final class SystemCountdownScheduler: CountdownScheduler {
    private var expiryTask: Task<Void, Never>?

    nonisolated init() {}

    var now: Date { .now }

    func scheduleExpiry(
        after delay: TimeInterval,
        _ onExpiry: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelExpiry()

        let clampedDelay = max(0, delay)
        expiryTask = Task(priority: .utility) {
            do {
                if clampedDelay > 0 {
                    try await Task.sleep(for: .seconds(clampedDelay), tolerance: .milliseconds(200))
                }
                try Task.checkCancellation()
            } catch {
                return
            }

            onExpiry()
        }
    }

    func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
    }
}
