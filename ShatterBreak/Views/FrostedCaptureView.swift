import SwiftUI

/// A captured screenshot as frosted glass: blur plus a slight dim.
///
/// The radius is in points, so a Retina and a non-Retina screen in the same break are
/// softened alike rather than betraying their pixel densities.
struct FrostedCaptureView: View {
    let image: CGImage

    private enum Frost {
        static let blurRadius: CGFloat = 5
        /// Pushes the blur's faded edges outside the frame, hiding the translucent border
        /// the kernel leaves where it samples past the screenshot's bounds.
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

#Preview("Frosted Capture") {
    if let image = PreviewWallpaper.image {
        FrostedCaptureView(image: image)
    } else {
        Color.gray
    }
}
