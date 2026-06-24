import SwiftUI

/// A frosted "material pill" style for the action buttons shown over the break
/// overlay. The translucent material plus a drop shadow give the buttons depth
/// against the frosted-glass capture, and the label uses the semantic primary
/// style so the system applies vibrancy for legibility over any wallpaper.
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
