import Foundation

@testable import ShatterBreak

/// Records overlay show/dismiss calls so tests can assert the overlay lifecycle that
/// the timer state machine drives. Replaces the former `OverlaySpy`: instead of a
/// one-method protocol, it vends a plain `OverlayPresenter` built from closures.
@MainActor
final class OverlayRecorder {
    private(set) var showCount = 0
    private(set) var dismissCount = 0

    var presenter: OverlayPresenter {
        OverlayPresenter(
            show: { [unowned self] _ in showCount += 1 },
            dismiss: { [unowned self] in dismissCount += 1 }
        )
    }
}
