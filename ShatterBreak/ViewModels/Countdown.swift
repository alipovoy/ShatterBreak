import Foundation

/// Owns the countdown mechanics for a single interval: the active deadline, the
/// frozen remaining time when paused, and the expiry monitoring driven by the
/// injected `TimerTickSource`.
///
/// The state machine in `TimerState` decides *when* to start, freeze, resume, or
/// clear a countdown; this type only tracks elapsed time and fires `onExpiry`
/// when the interval runs out.
@MainActor
final class Countdown {
    private let tickSource: any TimerTickSource

    /// The wall-clock moment the current interval ends, or `nil` when frozen or cleared.
    private var deadline: Date?

    /// The remaining time captured when the countdown is not actively running.
    private var frozenRemaining: TimeInterval = 0

    private var expiryTask: Task<Void, Never>?

    init(tickSource: any TimerTickSource) {
        self.tickSource = tickSource
    }

    /// The tick source's current notion of "now".
    var now: Date { tickSource.now }

    /// Whether a deadline is currently scheduled (i.e. the countdown is running).
    var isActive: Bool { deadline != nil }

    /// The remaining time at `referenceDate`: derived from the deadline while
    /// active, otherwise the frozen value.
    func remaining(at referenceDate: Date) -> TimeInterval {
        guard let deadline else { return frozenRemaining }
        return max(0, deadline.timeIntervalSince(referenceDate))
    }

    /// Starts counting down for `duration`, invoking `onExpiry` when it elapses.
    func begin(for duration: TimeInterval, onExpiry: @escaping @MainActor @Sendable () -> Void) {
        let clampedDuration = max(0, duration)
        frozenRemaining = clampedDuration
        deadline = tickSource.now.addingTimeInterval(clampedDuration)
        startMonitoring(onExpiry: onExpiry)
    }

    /// Resumes a frozen countdown for whatever time remained when it was frozen.
    func resume(onExpiry: @escaping @MainActor @Sendable () -> Void) {
        begin(for: frozenRemaining, onExpiry: onExpiry)
    }

    /// Freezes the countdown, preserving the remaining time and dropping the deadline.
    func freeze() {
        frozenRemaining = remaining(at: tickSource.now)
        stopMonitoring()
        deadline = nil
    }

    /// Clears all countdown state back to zero.
    func clear() {
        frozenRemaining = 0
        stopMonitoring()
        deadline = nil
    }

    /// Seeds the remaining time, re-arming an active deadline if one is running.
    ///
    /// Used by tests to place the countdown into a known state without driving it
    /// through a full work/rest cycle.
    func seed(remaining seconds: TimeInterval, onExpiry: @escaping @MainActor @Sendable () -> Void) {
        let clampedValue = max(0, seconds)
        frozenRemaining = clampedValue

        guard deadline != nil else { return }
        deadline = tickSource.now.addingTimeInterval(clampedValue)
        startMonitoring(onExpiry: onExpiry)
    }

    func stopMonitoring() {
        expiryTask?.cancel()
        expiryTask = nil
        tickSource.stop()
    }

    private func startMonitoring(onExpiry: @escaping @MainActor @Sendable () -> Void) {
        stopMonitoring()

        if tickSource.usesManualTicks {
            tickSource.start(onExpiry)
            return
        }

        guard let deadline else { return }

        let sleepDuration = max(0, deadline.timeIntervalSinceNow)
        expiryTask = Task(priority: .utility) { [weak self] in
            do {
                if sleepDuration > 0 {
                    try await Task.sleep(
                        for: .seconds(sleepDuration),
                        tolerance: .milliseconds(200)
                    )
                }
                try Task.checkCancellation()
            } catch {
                return
            }

            self?.fireExpiry(for: deadline, onExpiry: onExpiry)
        }
    }

    /// Fires `onExpiry` only if the deadline that scheduled this task is still current,
    /// guarding against a stale task firing after the countdown was re-armed.
    private func fireExpiry(for scheduledDeadline: Date, onExpiry: @MainActor @Sendable () -> Void) {
        guard deadline == scheduledDeadline else { return }
        onExpiry()
    }
}
