import SwiftUI

/// A reference date that advances exactly when the countdown's text can change. Read-only:
/// a loop that dies here leaves a stale label, never a stalled timer.
struct CountdownClock<Content: View>: View {
    let state: TimerState
    /// An off-screen popover should not wake the machine to redraw what nobody can see.
    var isActive = true
    /// Sets the cadence: the distance to the next visible change, once a minute in the
    /// power-save style.
    var displayStyle: CountdownDisplayStyle = .seconds
    @ViewBuilder var content: (Date) -> Content

    @State private var referenceDate = Date.now

    var body: some View {
        content(referenceDate)
            .task(id: taskKey) { await drive() }
    }

    /// The loop ends at zero and only a new key revives it, so it is keyed on the interval:
    /// back-to-back sessions share a mode.
    private var taskKey: CountdownClockKey {
        CountdownClockKey(
            intervalID: state.countdownIntervalID,
            mode: state.mode,
            isActive: isActive,
            displayStyle: displayStyle
        )
    }

    @MainActor
    private func drive() async {
        guard isActive else {
            referenceDate = state.now().date
            return
        }

        await displayStyle.driveCountdown(for: state) { referenceDate = $0 }
    }
}

private struct CountdownClockKey: Equatable {
    let intervalID: Int
    let mode: TimerState.Mode
    let isActive: Bool
    let displayStyle: CountdownDisplayStyle
}
