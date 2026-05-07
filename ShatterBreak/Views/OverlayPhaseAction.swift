enum OverlayPhaseAction: Equatable {
    case idle
    case playSound
    case animateShatterIntro
    case finishShatterIntro(playSound: Bool)

    static func resolve(
        phase: OverlayPresentationState.Phase,
        isShatterEffect: Bool,
        reduceMotion: Bool,
        playSoundEnabled: Bool,
        hasPlayedSound: Bool
    ) -> Self {
        let shouldPlaySound = playSoundEnabled && hasPlayedSound == false

        switch phase {
        case .plain:
            return isShatterEffect ? .idle : (shouldPlaySound ? .playSound : .idle)
        case .shatterIntro:
            if reduceMotion {
                return .finishShatterIntro(playSound: shouldPlaySound)
            }

            return .animateShatterIntro
        case .shattered:
            return .idle
        }
    }
}
