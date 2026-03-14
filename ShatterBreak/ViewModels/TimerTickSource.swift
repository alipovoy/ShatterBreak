import Foundation

@MainActor
protocol TimerTickSource: AnyObject {
    var now: Date { get }
    func start(_ handler: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
final class SystemTimerTickSource: TimerTickSource {
    private var task: Task<Void, Never>?

    nonisolated init() {}

    var now: Date { Date() }

    func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                handler()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    isolated deinit {
        task?.cancel()
    }
}
