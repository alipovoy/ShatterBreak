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
    let allowsShatterUpgrade: Bool

    var backgroundImage: CGImage?
    var phase: Phase = .plain

    init(effectType: EffectType, allowsShatterUpgrade: Bool) {
        self.effectType = effectType
        self.allowsShatterUpgrade = allowsShatterUpgrade
    }

    var isShatterEffect: Bool {
        effectType == .shatter
    }

    var showsCracks: Bool {
        isShatterEffect && phase == .shattered
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
