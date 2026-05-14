import Foundation

@testable import ShatterBreak

@MainActor
final class ManualTimerTickSource: TimerTickSource {
    private var handler: (@MainActor @Sendable () -> Void)?

    var now: Date
    let usesManualTicks = true

    nonisolated init(now: Date = .init(timeIntervalSince1970: 0)) {
        self.now = now
    }

    func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func advance(by interval: TimeInterval = 1) {
        now = now.addingTimeInterval(interval)
        handler?()
    }

    func elapse(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }

    func finish() {
        stop()
    }
}
