import SwiftUI

struct OverlayBackgroundView: View {
    let effectType: EffectType
    let backgroundImage: CGImage?
    let phase: OverlayPresentationState.Phase
    let shakeOffset: CGFloat

    private enum Dim {
        static let opacity: CGFloat = 0.85
    }

    var body: some View {
        Group {
            switch effectType {
            case .shatter:
                if let backgroundImage, phase != .plain {
                    FrostedCaptureView(image: backgroundImage)
                } else if phase == .plain {
                    Color.clear
                } else {
                    // Permission was granted but this display's capture failed; fall
                    // back to the live fogged desktop so the cracks read as
                    // intentional glass rather than a flat black panel.
                    FoggedDesktopView()
                }
            case .fogged:
                FoggedDesktopView()
            case .dimmed:
                Color.black.opacity(Dim.opacity)
            }
        }
        .offset(
            x: phase == .shatterIntro ? shakeOffset : 0,
            y: phase == .shatterIntro ? -shakeOffset : 0
        )
    }
}
