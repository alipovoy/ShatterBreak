import SwiftUI

struct CountdownTextView: View {
    let state: TimerState
    var isActive = true

    @State private var referenceDate = Date.now

    var body: some View {
        Text(state.formattedTimeRemaining(at: referenceDate))
            .task(id: CountdownTaskKey(mode: state.mode, isActive: isActive)) {
                await driveVisibleClockIfNeeded()
            }
    }

    @MainActor
    private func driveVisibleClockIfNeeded() async {
        referenceDate = Date.now

        guard isActive, state.isRunning else { return }

        while Task.isCancelled == false {
            let remaining = state.timeRemaining(at: referenceDate)
            guard remaining > 0 else { return }

            do {
                try await Task.sleep(
                    for: nextRefreshDelay(for: remaining),
                    tolerance: .milliseconds(100)
                )
            } catch {
                return
            }

            referenceDate = Date.now
        }
    }

    private func nextRefreshDelay(for remaining: TimeInterval) -> Duration {
        let fractionalSecond = remaining - floor(remaining)
        let secondsUntilRefresh = fractionalSecond > 0 ? fractionalSecond : 1
        return .seconds(secondsUntilRefresh)
    }
}

private struct CountdownTaskKey: Equatable {
    let mode: TimerState.Mode
    let isActive: Bool
}
