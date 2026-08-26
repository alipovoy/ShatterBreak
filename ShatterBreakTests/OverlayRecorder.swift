import Foundation

@testable import ShatterBreak

/// Records overlay show/dismiss calls so tests can assert the overlay lifecycle that
/// the timer state machine drives. Replaces the former `OverlaySpy`: instead of a
/// one-method protocol, it vends a plain `OverlayPresenter` built from closures.
///
/// The closures hold the recorder strongly, matching `OverlayPresenter.live`, which holds
/// its manager the same way. An unowned capture here made the recorder's lifetime every
/// caller's problem: anything dismissing an overlay from its own `deinit` crashed if the
/// recorder happened to be torn down first.
@MainActor
final class OverlayRecorder {
    private(set) var prepareCount = 0
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    /// The `settled` argument from the most recent `show` call, so tests can assert
    /// whether the break-end window was presented already settled (issue #76).
    private(set) var lastSettled: Bool?
    /// The timer the most recent `show` was given, so tests can inspect what an overlay
    /// would be rendering.
    private(set) var lastState: TimerState?

    var presenter: OverlayPresenter {
        OverlayPresenter(
            prepare: { self.prepareCount += 1 },
            show: { state, style in
                self.showCount += 1
                self.lastSettled = style == .settled
                self.lastState = state
            },
            dismiss: { self.dismissCount += 1 }
        )
    }
}
