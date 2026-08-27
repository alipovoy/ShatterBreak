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
                    // Capture failed for this display; fall back to the fogged desktop so
                    // the cracks read as glass rather than a flat black panel.
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

/// One effect over the same desktop, labelled, for the comparison preview below.
private struct EffectSample: View {
    let effect: EffectType
    let desktop: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            Text(effect.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                if let desktop {
                    Image(decorative: desktop, scale: 1).resizable()
                }
                OverlayBackgroundView(
                    effectType: effect,
                    backgroundImage: desktop,
                    phase: .shattered,
                    shakeOffset: 0
                )
            }
            .frame(width: 240, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// The three effects over one desktop, since each is a treatment of the same screen and the
// question is how much of it survives.
//
// Fogged shows its tint without its blur, and no preview can do better: behind-window
// vibrancy blurs what the window server composites beneath the overlay, which in a preview
// is nothing.
#Preview("Break effects") {
    let desktop = PreviewWallpaper.image

    HStack(spacing: 12) {
        ForEach(EffectType.allCases) { effect in
            EffectSample(effect: effect, desktop: desktop)
        }
    }
    .padding()
}
