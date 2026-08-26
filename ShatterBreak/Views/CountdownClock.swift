import SwiftUI

/// Supplies a reference date that advances exactly when the countdown's display can next
/// change, and no sooner.
///
/// **Read-only by construction.** It never touches the plan and never emits an effect —
/// the timer itself is driven by ``TimerState``'s own clock, which keeps running whether
/// or not anything is on screen. So a drive loop that dies here leaves a stale label and
/// nothing else: cosmetic, not a stall. Historically the two were confused, and a dead
/// view loop was indistinguishable from a stuck timer (issue #108).
///
/// One implementation for every countdown on screen. The menu bar, the popover and the
/// break overlay all used to keep their own near-copies of this loop, each with its own
/// idea of when to restart.
struct CountdownClock<Content: View>: View {
    let state: TimerState
    /// Whether the view is actually visible. An off-screen popover should not wake the
    /// machine to redraw something nobody can see.
    var isActive = true
    /// Determines the cadence: exactly the distance to the next visible change, which is
    /// once a minute in the power-save style (issue #78).
    var displayStyle: CountdownDisplayStyle = .seconds
    @ViewBuilder var content: (Date) -> Content

    @State private var referenceDate = Date.now

    var body: some View {
        content(referenceDate)
            .task(id: taskKey) { await drive() }
    }

    /// Restarts the visible clock whenever the interval being counted changes.
    ///
    /// The interval is the part that matters: the loop below ends when it reaches zero, so
    /// only a new key can revive it, and back-to-back sessions in the same mode — work
    /// auto-resuming after a break, or after an absence that stood in for one — would
    /// otherwise leave it dead with the last frame still on screen (issue #108).
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
