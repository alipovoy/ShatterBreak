import SwiftUI

struct CountdownTextView: View {
    let state: TimerState
    var isActive = true
    var displayStyle: CountdownDisplayStyle = .seconds

    @State private var referenceDate = Date.now

    var body: some View {
        Text(displayStyle.text(forRemaining: state.timeRemaining(at: referenceDate)))
            .task(id: taskKey) {
                await driveVisibleClockIfNeeded()
            }
    }

    /// Restarts the visible clock whenever the interval being counted changes.
    ///
    /// The interval is the part that matters: the loop below ends when it reaches zero, so
    /// only a new key can revive it, and back-to-back sessions in the same mode — work
    /// auto-resuming after a break, or after an absence that stood in for one — would
    /// otherwise leave it dead with the last frame still on screen (issue #108).
    private var taskKey: CountdownTaskKey {
        CountdownTaskKey(
            intervalID: state.countdownIntervalID,
            mode: state.mode,
            isActive: isActive,
            displayStyle: displayStyle
        )
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
                    for: displayStyle.nextRefreshDelay(forRemaining: remaining),
                    tolerance: displayStyle.refreshTolerance(forRemaining: remaining)
                )
            } catch {
                return
            }

            referenceDate = Date.now
        }
    }
}

private struct CountdownTaskKey: Equatable {
    let intervalID: Int
    let mode: TimerState.Mode
    let isActive: Bool
    let displayStyle: CountdownDisplayStyle
}
