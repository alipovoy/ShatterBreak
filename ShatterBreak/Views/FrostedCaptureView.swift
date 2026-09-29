import SwiftUI

/// The blur radius is in points, so Retina and non-Retina screens soften alike.
struct FrostedCaptureView: View {
    let image: CGImage

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(PreferenceKeys.reduceMotion) private var reduceMotion = PreferenceDefaults.reduceMotion

    private enum Frost {
        static let blurRadius: CGFloat = 5
        /// Pushes the blur's translucent edge outside the frame. Reduce motion skips it: the
        /// capture appearing at another size reads as a zoom.
        static let edgeBleedScale: CGFloat = 1.05
        static let dimOpacity: CGFloat = 0.2
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .blur(radius: Frost.blurRadius)
            .scaleEffect(reduceMotion || accessibilityReduceMotion ? 1 : Frost.edgeBleedScale)
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
