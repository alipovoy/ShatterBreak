import SwiftUI

struct OverlayBackgroundView: View {
    let isShatterEffect: Bool
    let backgroundImage: CGImage?
    let phase: OverlayPresentationState.Phase
    let shakeOffset: CGFloat

    var body: some View {
        Group {
            if isShatterEffect {
                if let backgroundImage, phase != .plain {
                    Image(decorative: backgroundImage, scale: 1)
                        .resizable()
                } else if phase == .plain {
                    Color.clear
                } else {
                    Color.black.opacity(0.85)
                }
            } else {
                Color.black.opacity(0.85)
            }
        }
        .offset(
            x: phase == .shatterIntro ? shakeOffset : 0,
            y: phase == .shatterIntro ? -shakeOffset : 0
        )
    }
}

#Preview("Overlay Background") {
    OverlayBackgroundView(
        isShatterEffect: true,
        backgroundImage: nil,
        phase: .shattered,
        shakeOffset: 0
    )
}
