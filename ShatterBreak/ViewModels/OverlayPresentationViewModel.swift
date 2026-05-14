import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayPresentationViewModel {
    struct Dependencies {
        var playGlassSound: @MainActor () -> Void
        var sleep: @MainActor (Duration) async throws -> Void

        static let live = Self(
            playGlassSound: {
                NSSound(named: "Glass")?.play()
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            }
        )
    }

    private enum Constants {
        static let shakeDistance: CGFloat = 10
        static let shakeDuration = 0.05
        static let shakeRepeatCount = 20
        static let shatterIntroDelay: Duration = .milliseconds(900)
    }

    var shakeOffset: CGFloat = 0

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var hasPlayedSound = false

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func handlePresentationPhase(
        presentation: OverlayPresentationState,
        reduceMotion: Bool,
        playSoundEnabled: Bool
    ) async {
        switch OverlayPhaseAction.resolve(
            phase: presentation.phase,
            isShatterEffect: presentation.isShatterEffect,
            reduceMotion: reduceMotion,
            playSoundEnabled: playSoundEnabled,
            hasPlayedSound: hasPlayedSound
        ) {
        case .idle:
            shakeOffset = 0
        case .playSound:
            shakeOffset = 0
            playGlassSoundIfNeeded(playSoundEnabled: playSoundEnabled)
        case .finishShatterIntro(let playSound):
            completeShatterIntro(
                presentation: presentation,
                playSound: playSound,
                playSoundEnabled: playSoundEnabled
            )
        case .animateShatterIntro:
            await animateShatterIntro(
                presentation: presentation,
                playSoundEnabled: playSoundEnabled
            )
        }
    }

    private func animateShatterIntro(
        presentation: OverlayPresentationState,
        playSoundEnabled: Bool
    ) async {
        shakeOffset = 0
        withAnimation(.spring(duration: Constants.shakeDuration).repeatCount(Constants.shakeRepeatCount, autoreverses: true)) {
            shakeOffset = Constants.shakeDistance
        }

        do {
            try await dependencies.sleep(Constants.shatterIntroDelay)
            try Task.checkCancellation()
        } catch {
            return
        }

        guard presentation.phase == .shatterIntro else { return }
        completeShatterIntro(
            presentation: presentation,
            playSound: true,
            playSoundEnabled: playSoundEnabled
        )
    }

    private func completeShatterIntro(
        presentation: OverlayPresentationState,
        playSound: Bool,
        playSoundEnabled: Bool
    ) {
        shakeOffset = 0
        presentation.finishShatterIntro()
        if playSound {
            playGlassSoundIfNeeded(playSoundEnabled: playSoundEnabled)
        }
    }

    private func playGlassSoundIfNeeded(playSoundEnabled: Bool) {
        guard playSoundEnabled, hasPlayedSound == false else { return }
        hasPlayedSound = true
        dependencies.playGlassSound()
    }
}
