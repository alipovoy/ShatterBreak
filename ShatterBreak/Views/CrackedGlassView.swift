import SwiftUI

/// The visual treatment used to render the cracked-glass fracture lines.
///
/// All three keep the cracks readable over the frosted capture by drawing the
/// highlights as *additive* light (`.plusLighter`) rather than flat white paint —
/// that is what makes a fracture read as glass catching light instead of a dark
/// drawn line. They differ only in how far the effect is pushed.
enum CrackStyle: String, CaseIterable, Identifiable {
    /// Additive fracture lines over a thin, offset dark stroke for depth.
    case glint
    /// ``glint`` plus bright twinkles where secondary cracks branch off.
    case sparkle
    /// ``glint`` plus a soft blurred glow hugging the main cracks (wet sheen).
    case glossy

    var id: Self { self }

    var label: String {
        switch self {
        case .glint: "Glint"
        case .sparkle: "Sparkle"
        case .glossy: "Glossy"
        }
    }
}

struct CrackedGlassView: View {
    var style: CrackStyle = .glint
    private let generator = CrackedGlassGenerator()
    @State private var cracks: CrackedGlass?

    var body: some View {
        CrackedGlassCanvas(cracks: cracks, style: style)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                var rng = SystemRandomNumberGenerator()
                cracks = generator.generate(size: newSize, using: &rng)
            }
            .allowsHitTesting(false)
    }
}

/// Purely presentational rendering of pre-generated ``CrackedGlass`` geometry in a
/// chosen ``CrackStyle``. Split out from ``CrackedGlassView`` so previews can render
/// several styles over the *same* fracture geometry for a fair comparison.
struct CrackedGlassCanvas: View {
    let cracks: CrackedGlass?
    let style: CrackStyle

    var body: some View {
        Canvas { context, _ in
            guard let cracks else { return }
            switch style {
            case .glint: Self.drawGlint(cracks, in: context)
            case .sparkle: Self.drawSparkle(cracks, in: context)
            case .glossy: Self.drawGlossy(cracks, in: context)
            }
        }
        .id(cracks?.mainCracks.boundingRect)
    }

    // MARK: - Styles

    /// Specular fracture lines: additive white highlights over a thin, offset dark
    /// stroke that reads as depth rather than a heavy outline.
    private static func drawGlint(_ cracks: CrackedGlass, in context: GraphicsContext) {
        var shadow = context
        shadow.translateBy(x: 0.75, y: 0.75)
        shadow.stroke(cracks.mainCracks, with: .color(.black.opacity(0.35)), lineWidth: 2)
        shadow.stroke(cracks.webCracks, with: .color(.black.opacity(0.2)), lineWidth: 1)

        var light = context
        light.blendMode = .plusLighter
        light.stroke(cracks.mainCracks, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        light.stroke(cracks.webCracks, with: .color(.white.opacity(0.55)), lineWidth: 0.5)

        fillLight(cracks.shatterCenter, radius: 5, opacity: 0.9, in: light)
    }

    /// ``drawGlint`` plus bright twinkles where secondary cracks branch off the main
    /// fractures, so light visibly sparkles at the junctions.
    private static func drawSparkle(_ cracks: CrackedGlass, in context: GraphicsContext) {
        drawGlint(cracks, in: context)

        var light = context
        light.blendMode = .plusLighter
        for point in junctions(of: cracks) {
            fillLight(point, radius: 5, opacity: 0.18, in: light)
            fillLight(point, radius: 1.4, opacity: 0.95, in: light)
        }
        fillLight(cracks.shatterCenter, radius: 9, opacity: 0.25, in: light)
        fillLight(cracks.shatterCenter, radius: 3, opacity: 0.95, in: light)
    }

    /// ``drawGlint`` plus a soft blurred glow hugging the main cracks for a wet,
    /// glossy sheen.
    private static func drawGlossy(_ cracks: CrackedGlass, in context: GraphicsContext) {
        var glow = context
        glow.blendMode = .plusLighter
        glow.addFilter(.blur(radius: 4))
        glow.stroke(cracks.mainCracks, with: .color(.white.opacity(0.3)), lineWidth: 5)

        drawGlint(cracks, in: context)
    }

    // MARK: - Drawing helpers

    private static func fillLight(
        _ center: CGPoint,
        radius: CGFloat,
        opacity: Double,
        in context: GraphicsContext
    ) {
        context.fill(dot(at: center, radius: radius), with: .color(.white.opacity(opacity)))
    }

    private static func dot(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    /// The points where secondary cracks branch off the main fractures — the natural
    /// junctions to twinkle.
    private static func junctions(of cracks: CrackedGlass) -> [CGPoint] {
        var points: [CGPoint] = []
        cracks.webCracks.forEach { element in
            if case .move(let to) = element {
                points.append(to)
            }
        }
        return points
    }
}

#Preview("Crack styles") {
    let size = CGSize(width: 300, height: 460)
    var rng = SystemRandomNumberGenerator()
    let cracks = CrackedGlassGenerator().generate(size: size, using: &rng)
    let wallpaper = ImageRenderer(content: PreviewWallpaper()).cgImage

    HStack(spacing: 1) {
        ForEach(CrackStyle.allCases) { style in
            ZStack {
                if let wallpaper {
                    FrostedCaptureView(image: wallpaper)
                } else {
                    Color.gray
                }

                CrackedGlassCanvas(cracks: cracks, style: style)

                VStack {
                    Spacer()
                    Text(style.label)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5), in: .capsule)
                        .padding(.bottom, 12)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}
