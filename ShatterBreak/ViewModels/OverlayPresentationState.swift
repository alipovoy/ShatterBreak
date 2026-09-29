import CoreGraphics
import Observation

@MainActor
@Observable
final class OverlayPresentationState {
    enum Phase: Equatable {
        case plain
        case shatterIntro
        case shattered
    }

    let effectType: EffectType

    /// No entrance and no sound: an absence served as the break (issue #76), or the display
    /// joined a break already running (issue #94).
    let settled: Bool

    var backgroundImage: CGImage?
    var phase: Phase = .plain

    init(effectType: EffectType, settled: Bool = false) {
        self.effectType = effectType
        self.settled = settled
    }

    var isShatterEffect: Bool {
        effectType == .shatter
    }

    var showsCracks: Bool {
        switch effectType {
        case .shatter:
            phase == .shattered
        case .fogged:
            true
        case .dimmed:
            false
        }
    }

    /// A settled overlay skips straight to `.shattered`.
    func startShatter(with image: CGImage?) {
        guard isShatterEffect, phase == .plain else { return }

        backgroundImage = image
        phase = settled ? .shattered : .shatterIntro
    }

    func finishShatterIntro() {
        guard phase == .shatterIntro else { return }
        phase = .shattered
    }
}
