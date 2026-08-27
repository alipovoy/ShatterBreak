import SwiftUI

/// A frosted "material pill" for the overlay's action buttons. The semantic primary label
/// style lets the system apply vibrancy, for legibility over any wallpaper.
struct OverlayActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .font(.title2)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("OverlayActionButtonStyle") {
    // Over the frosted desktop: material and vibrancy have nothing to work against on a
    // flat background.
    let desktop = PreviewWallpaper.image

    ZStack {
        if let desktop {
            FrostedCaptureView(image: desktop)
        } else {
            Color.gray
        }

        HStack(spacing: 16) {
            Button("Postpone", action: { })
            Button("I'm back", action: { })
        }
        .buttonStyle(OverlayActionButtonStyle())
    }
    .frame(width: 480, height: 200)
}
