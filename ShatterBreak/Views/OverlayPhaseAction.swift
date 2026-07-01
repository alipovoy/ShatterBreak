enum OverlayPhaseAction: Equatable {
    case idle
    case playSound
    case animateShatterIntro
    case finishShatterIntro(playSound: Bool)

    static func resolve(
        phase: OverlayPresentationState.Phase,
        isShatterEffect: Bool,
        reduceMotion: Bool,
        shouldPlaySound: Bool,
        isSettled: Bool
    ) -> Self {
        let playsSound = shouldPlaySound && isSettled == false

        switch phase {
        case .plain:
            return isShatterEffect ? .idle : (playsSound ? .playSound : .idle)
        case .shatterIntro:
            if reduceMotion {
                return .finishShatterIntro(playSound: playsSound)
            }

            return .animateShatterIntro
        case .shattered:
            return .idle
        }
    }
}
