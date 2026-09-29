import SwiftUI

struct CrackedGlass: Equatable {
    var mainCracks: Path
    var webCracks: Path
    var shatterCenter: CGPoint
}

struct CrackedGlassGenerator {
    /// A fraction of each axis: a fixed offset read as centred on large displays.
    private static let impactJitterFraction: CGFloat = 0.15

    func generate(
        size: CGSize,
        using rng: inout some RandomNumberGenerator
    ) -> CrackedGlass? {
        guard size.width > 0, size.height > 0 else { return nil }

        let jitter = Self.impactJitterFraction
        let center = CGPoint(
            x: size.width * (0.5 + CGFloat.random(in: -jitter...jitter, using: &rng)),
            y: size.height * (0.5 + CGFloat.random(in: -jitter...jitter, using: &rng))
        )

        var main = Path()
        var web = Path()

        let numMainCracks = Int.random(in: 12...18, using: &rng)
        let maxRadius = max(size.width, size.height) * 1.2

        for crackIndex in 0..<numMainCracks {
            let baseAngle = (Double(crackIndex) / Double(numMainCracks)) * .pi * 2.0
            let angle = baseAngle + Double.random(in: -0.2...0.2, using: &rng)

            var currentPoint = center
            main.move(to: currentPoint)

            var currentRadius: CGFloat = 0

            while currentRadius < maxRadius {
                let step = CGFloat.random(in: 20...80, using: &rng)
                currentRadius += step

                let drift = CGFloat.random(in: -15...15, using: &rng)

                let nextX = center.x + currentRadius * cos(angle) + drift * sin(angle)
                let nextY = center.y + currentRadius * sin(angle) - drift * cos(angle)

                currentPoint = CGPoint(x: nextX, y: nextY)
                main.addLine(to: currentPoint)

                if CGFloat.random(in: 0...1, using: &rng) > 0.6 {
                    web.move(to: currentPoint)

                    let webAngle = angle + Double.random(in: -1.0...1.0, using: &rng)
                    let webLength = CGFloat.random(in: 15...60, using: &rng)

                    let webX = currentPoint.x + webLength * cos(webAngle)
                    let webY = currentPoint.y + webLength * sin(webAngle)

                    web.addLine(to: CGPoint(x: webX, y: webY))
                }
            }
        }

        return CrackedGlass(mainCracks: main, webCracks: web, shatterCenter: center)
    }
}
