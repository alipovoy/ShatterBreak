import SwiftUI

/// Supplies a reference date that advances exactly when the countdown's display can next
/// change, and no sooner.
///
/// Read-only by construction: the timer runs on ``TimerState``'s own clock, so a drive loop
/// that dies here leaves a stale label, not a stalled timer. The two were once confused,
/// and a dead view loop was indistinguishable from a stuck timer (#108).
///
/// One implementation for every countdown on screen; the menu bar, popover and overlay all
/// used to keep near-copies with their own ideas of when to restart.
struct CountdownClock<Content: View>: View {
    let state: TimerState
    /// An off-screen popover should not wake the machine to redraw what nobody can see.
    var isActive = true
    /// Sets the cadence: the distance to the next visible change, once a minute in the
    /// power-save style (#78).
    var displayStyle: CountdownDisplayStyle = .seconds
    @ViewBuilder var content: (Date) -> Content

    @State private var referenceDate = Date.now

    var body: some View {
        content(referenceDate)
            .task(id: taskKey) { await drive() }
    }

    /// Restarts the loop when the interval changes.
    ///
    /// The loop ends at zero, so only a new key revives it. Keyed on anything coarser,
    /// back-to-back sessions in the same mode leave it dead on the last frame (#108).
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
        referenceDate = .now

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

            referenceDate = .now
        }
    }
}

private struct CountdownClockKey: Equatable {
    let intervalID: Int
    let mode: TimerState.Mode
    let isActive: Bool
    let displayStyle: CountdownDisplayStyle
}
