import SwiftUI

/// The blur radius is in points, so Retina and non-Retina screens soften alike.
struct FrostedCaptureView: View {
    let image: CGImage

    private enum Frost {
        static let blurRadius: CGFloat = 5
        /// Pushes the blur's translucent edge outside the frame.
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
