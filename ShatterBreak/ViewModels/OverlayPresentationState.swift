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

    /// Whether this overlay should present already settled — no shake intro or entrance
    /// sound — because an absence already served as the break (issue #76).
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

    /// Applies a captured background and advances past `.plain`. A settled overlay
    /// (issue #76: the break-end window for an absence that already served as the
    /// break) skips straight to `.shattered` — no shake intro, no entrance sound.
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
