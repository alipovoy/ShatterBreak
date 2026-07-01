import Foundation

@testable import ShatterBreak

/// Records overlay show/dismiss calls so tests can assert the overlay lifecycle that
/// the timer state machine drives. Replaces the former `OverlaySpy`: instead of a
/// one-method protocol, it vends a plain `OverlayPresenter` built from closures.
@MainActor
final class OverlayRecorder {
    private(set) var showCount = 0
    private(set) var dismissCount = 0
    /// The `settled` argument from the most recent `show` call, so tests can assert
    /// whether the break-end window was presented already settled (issue #76).
    private(set) var lastSettled: Bool?

    var presenter: OverlayPresenter {
        OverlayPresenter(
            show: { [unowned self] _, style in
                showCount += 1
                lastSettled = style == .settled
            },
            dismiss: { [unowned self] in dismissCount += 1 }
        )
    }
}
