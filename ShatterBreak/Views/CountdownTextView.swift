import SwiftUI

struct CountdownTextView: View {
    let state: TimerState
    var isActive = true
    var displayStyle: CountdownDisplayStyle = .seconds

    @State private var referenceDate = Date.now

    var body: some View {
        Text(displayStyle.text(forRemaining: state.timeRemaining(at: referenceDate)))
            .task(id: CountdownTaskKey(mode: state.mode, isActive: isActive, displayStyle: displayStyle)) {
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
    let mode: TimerState.Mode
    let isActive: Bool
    let displayStyle: CountdownDisplayStyle
}
