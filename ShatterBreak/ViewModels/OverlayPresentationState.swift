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

    var backgroundImage: CGImage?
    var phase: Phase = .plain

    init(effectType: EffectType) {
        self.effectType = effectType
    }

    var isShatterEffect: Bool {
        effectType == .shatter
    }

    /// Whether the cracked-glass overlay is drawn. The shatter effect only cracks
    /// once it has settled into the shattered phase; the fogged effect always shows
    /// cracks over its live glass; the dimmed effect never cracks.
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

    func startShatter(with image: CGImage?) {
        guard isShatterEffect, phase == .plain else { return }

        backgroundImage = image
        phase = .shatterIntro
    }

    func finishShatterIntro() {
        guard phase == .shatterIntro else { return }
        phase = .shattered
    }
}
