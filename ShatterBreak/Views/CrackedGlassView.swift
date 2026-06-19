import SwiftUI

struct CrackedGlassView: View {
    private let generator = CrackedGlassGenerator()
    @State private var cracks: CrackedGlass?

    var body: some View {
        Canvas { context, _ in
            guard let cracks else { return }

            context.stroke(cracks.mainCracks, with: .color(.black.opacity(0.5)), lineWidth: 3)
            context.stroke(cracks.webCracks, with: .color(.black.opacity(0.3)), lineWidth: 1.5)

            context.stroke(cracks.mainCracks, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            context.stroke(cracks.webCracks, with: .color(.white.opacity(0.6)), lineWidth: 0.5)

            let center = cracks.shatterCenter
            let impactRect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: impactRect), with: .color(.white.opacity(0.9)))
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
}

#Preview("CrackedGlassView") {
    CrackedGlassView()
        .frame(width: 400, height: 400)
        .background(.gray)
}
