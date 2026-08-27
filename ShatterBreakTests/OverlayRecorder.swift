import Foundation

@testable import ShatterBreak

/// Records overlay calls, so tests can assert the lifecycle the state machine drives.
///
/// The closures hold the recorder strongly, matching `OverlayPresenter.live`. An unowned
/// capture crashed anything dismissing an overlay from its own `deinit`, which could run
/// after the recorder was torn down.
@MainActor
final class OverlayRecorder {
    private(set) var prepareCount = 0
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    /// Whether the last presentation was already settled.
    private(set) var lastSettled: Bool?
    /// The timer the last `show` was given, for inspecting what an overlay would render.
    private(set) var lastState: TimerState?
    /// What is on screen now, for callers that check whether the window is still theirs.
    private(set) var presented: TimerState?

    var presenter: OverlayPresenter {
        OverlayPresenter(
            prepare: { self.prepareCount += 1 },
            show: { state, style in
                self.showCount += 1
                self.lastSettled = style == .settled
                self.lastState = state
                self.presented = state
            },
            dismiss: {
                self.dismissCount += 1
                self.presented = nil
            },
            presenting: { self.presented }
        )
    }
}
