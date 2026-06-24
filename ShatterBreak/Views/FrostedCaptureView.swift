import SwiftUI

/// Renders a captured screenshot as frosted glass: a resolution-independent blur
/// plus a slight dim.
///
/// The blur radius is measured in points, so every display is softened by the same
/// amount regardless of its backing scale. That keeps a Retina and a non-Retina
/// screen in the same break looking alike instead of betraying their different
/// pixel densities, and obscures on-screen content while the user steps away.
struct FrostedCaptureView: View {
    let image: CGImage

    private enum Frost {
        static let blurRadius: CGFloat = 8
        /// Enlarges the blurred image so its faded edges fall outside the frame,
        /// hiding the translucent border the blur kernel leaves where it samples
        /// past the screenshot's bounds.
        static let edgeBleedScale: CGFloat = 1.05
        static let dimOpacity: CGFloat = 0.2
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .blur(radius: Frost.blurRadius)
            .scaleEffect(Frost.edgeBleedScale)
            .overlay(Color.black.opacity(Frost.dimOpacity))
            .clipped()
    }
}
