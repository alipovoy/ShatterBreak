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
        // Keep the sleep loop off the main actor so the first visible second
        // doesn't wait behind UI work and appear to skip a value.
        task = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                    try Task.checkCancellation()
                } catch {
                    return
                }

                await handler()
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
