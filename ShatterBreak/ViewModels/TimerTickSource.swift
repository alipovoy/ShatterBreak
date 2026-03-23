import Foundation

@MainActor
protocol TimerTickSource: AnyObject {
    var now: Date { get }
    var usesManualTicks: Bool { get }
    func start(_ handler: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
final class SystemTimerTickSource: TimerTickSource {
    nonisolated init() {}

    var now: Date { Date() }
    let usesManualTicks = false

    func start(_ handler: @escaping @MainActor @Sendable () -> Void) {}
    func stop() {}
}
