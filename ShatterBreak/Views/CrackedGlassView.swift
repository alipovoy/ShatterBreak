import SwiftUI

struct CrackedGlassView: View {
    private let generator = CrackedGlassGenerator()
    @State private var cracks: CrackedGlass?

    var body: some View {
        Canvas { context, _ in
            guard let cracks else { return }
            Self.draw(cracks, in: context)
        }
        .id(cracks?.mainCracks.boundingRect)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            var rng = SystemRandomNumberGenerator()
            cracks = generator.generate(size: newSize, using: &rng)
        }
        .allowsHitTesting(false)
    }

    /// Renders the fractures as glass catching light: additive white highlights
    /// (`.plusLighter`) over a thin, offset dark stroke that reads as depth rather
    /// than a heavy outline. Additive blending is what keeps the cracks glinting
    /// instead of looking like flat dark lines over the frosted capture.
    private static func draw(_ cracks: CrackedGlass, in context: GraphicsContext) {
        var shadow = context
        shadow.translateBy(x: 0.75, y: 0.75)
        shadow.stroke(cracks.mainCracks, with: .color(.black.opacity(0.35)), lineWidth: 2)
        shadow.stroke(cracks.webCracks, with: .color(.black.opacity(0.2)), lineWidth: 1)

        var light = context
        light.blendMode = .plusLighter
        light.stroke(cracks.mainCracks, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        light.stroke(cracks.webCracks, with: .color(.white.opacity(0.55)), lineWidth: 0.5)

        let center = cracks.shatterCenter
        let radius: CGFloat = 5
        let impact = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        light.fill(impact, with: .color(.white.opacity(0.9)))
    }
}

#Preview("CrackedGlassView") {
    let wallpaper = ImageRenderer(content: PreviewWallpaper()).cgImage

    ZStack {
        if let wallpaper {
            FrostedCaptureView(image: wallpaper)
        } else {
            Color.gray
        }

        CrackedGlassView()
    }
    .frame(width: 480, height: 360)
}
