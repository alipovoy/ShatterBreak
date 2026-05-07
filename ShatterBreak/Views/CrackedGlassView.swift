import SwiftUI

struct CrackedGlassView: View {
    @State private var mainCracks = Path()
    @State private var webCracks = Path()
    @State private var shatterCenter: CGPoint = .zero
    @State private var isGenerated = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard isGenerated else { return }

                context.stroke(mainCracks, with: .color(.black.opacity(0.5)), lineWidth: 3)
                context.stroke(webCracks, with: .color(.black.opacity(0.3)), lineWidth: 1.5)

                context.stroke(mainCracks, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                context.stroke(webCracks, with: .color(.white.opacity(0.6)), lineWidth: 0.5)

                let impactRect = CGRect(x: shatterCenter.x - 5, y: shatterCenter.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: impactRect), with: .color(.white.opacity(0.9)))
            }
            .task(id: geometry.size) {
                // This runs on MainActor inheriting from view context.
                generateCracks(size: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private func generateCracks(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let center = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -100...100),
            y: size.height * 0.5 + CGFloat.random(in: -100...100)
        )

        var main = Path()
        var web = Path()

        let numMainCracks = Int.random(in: 12...18)
        let maxRadius = max(size.width, size.height) * 1.2

        for i in 0..<numMainCracks {
            let baseAngle = (Double(i) / Double(numMainCracks)) * .pi * 2.0
            let angle = baseAngle + Double.random(in: -0.2...0.2)

            var currentPoint = center
            main.move(to: currentPoint)

            var currentRadius: CGFloat = 0

            while currentRadius < maxRadius {
                let step = CGFloat.random(in: 20...80)
                currentRadius += step

                let drift = CGFloat.random(in: -15...15)

                let nextX = center.x + currentRadius * cos(angle) + drift * sin(angle)
                let nextY = center.y + currentRadius * sin(angle) - drift * cos(angle)

                currentPoint = CGPoint(x: nextX, y: nextY)
                main.addLine(to: currentPoint)

                if CGFloat.random(in: 0...1) > 0.6 {
                    web.move(to: currentPoint)

                    let webAngle = angle + Double.random(in: -1.0...1.0)
                    let webLength = CGFloat.random(in: 15...60)

                    let webX = currentPoint.x + webLength * cos(webAngle)
                    let webY = currentPoint.y + webLength * sin(webAngle)

                    web.addLine(to: CGPoint(x: webX, y: webY))
                }
            }
        }

        shatterCenter = center
        mainCracks = main
        webCracks = web
        isGenerated = true
    }
}

#Preview("CrackedGlassView") {
    CrackedGlassView()
}
