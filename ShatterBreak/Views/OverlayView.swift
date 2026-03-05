import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var state: TimerState
    var bgImage: CGImage?
    var hasPermission: Bool

    @State private var phase = 0 // Controls animation sequence
    @State private var shakeOffset: CGFloat = 0

    @AppStorage("playSound") private var playSound: Bool = true
    @AppStorage("effectType") private var effectType: EffectType = .shatter

    var body: some View {
        ZStack {
            if effectType == .shatter, hasPermission, let cgImage = bgImage {
                Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    .resizable()
                    .offset(x: phase == 1 ? shakeOffset : 0, y: phase == 1 ? -shakeOffset : 0)
            } else {
                Color.black.opacity(0.85) // Fallback if no permission or capture failed
            }

            if phase == 2 || (!hasPermission && phase > 0) {
                CrackedGlassView()

                VStack {
                    Text("Time to rest")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 5)

                    Text(timeString(from: state.timeRemaining))
                        .font(.system(size: 80, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 5)
                }
            }
        }
        // Use .task to manage the animation lifecycle, automatically cancelling on view dismissal
        .task {
            await runAnimationSequence()
        }
    }

    private func runAnimationSequence() async {
        if (effectType == .shatter && hasPermission) {
            if Task.isCancelled { return }

            // Shake the screen
            phase = 1
            withAnimation(Animation.linear(duration: 0.05).repeatCount(15, autoreverses: true)) {
                shakeOffset = 15
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000) // wait before shatter the window

        }
        phase = 2

        if playSound {
            NSSound(named: "Glass")?.play()
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct CrackedGlassView: View {
    @State private var mainCracks = Path()
    @State private var webCracks = Path()
    @State private var shatterCenter: CGPoint = .zero
    @State private var isGenerated = false

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                if !isGenerated { return }

                // Render the paths
                // Dark underlay for depth (simulating the edge of thick glass)
                context.stroke(mainCracks, with: .color(.black.opacity(0.5)), lineWidth: 3)
                context.stroke(webCracks,  with: .color(.black.opacity(0.3)), lineWidth: 1.5)

                // White overlay for light catching the fracture
                context.stroke(mainCracks, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                context.stroke(webCracks,  with: .color(.white.opacity(0.6)), lineWidth: 0.5)

                // Shatter origin impact mark
                let impactRect = CGRect(x: shatterCenter.x - 5, y: shatterCenter.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: impactRect), with: .color(.white.opacity(0.9)))
            }
            .onAppear {
                generateCracks(size: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                generateCracks(size: newSize)
            }
        }
        // Ensure the Canvas doesn't block clicks from passing through if needed
        .allowsHitTesting(false)
    }

    private func generateCracks(size: CGSize) {
        if size.width == 0 || size.height == 0 { return }

        // Pick a shatter origin point near the center of the given area
        let center = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -100...100),
            y: size.height * 0.5 + CGFloat.random(in: -100...100)
        )

        var main = Path()
        var web = Path()

        let numMainCracks = Int.random(in: 12...18)
        let maxRadius = max(size.width, size.height) * 1.2

        // Generate radial cracks shooting outwards from the center
        for i in 0..<numMainCracks {
            // Distribute angles roughly evenly, with some randomness
            let baseAngle = (Double(i) / Double(numMainCracks)) * .pi * 2.0
            let angle = baseAngle + Double.random(in: -0.2...0.2)

            var currentPoint = center
            main.move(to: currentPoint)

            var currentRadius: CGFloat = 0

            // Trace the crack outwards until it leaves the screen area
            while currentRadius < maxRadius {
                // Step length
                let step = CGFloat.random(in: 20...80)
                currentRadius += step

                // Jitter perpendicular to the crack direction
                let drift = CGFloat.random(in: -15...15)

                let nextX = center.x + currentRadius * cos(angle) + drift * sin(angle)
                let nextY = center.y + currentRadius * sin(angle) - drift * cos(angle)

                currentPoint = CGPoint(x: nextX, y: nextY)
                main.addLine(to: currentPoint)

                // Occasionally spawn smaller "web" fractures
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

        DispatchQueue.main.async {
            self.shatterCenter = center
            self.mainCracks = main
            self.webCracks = web
            self.isGenerated = true
        }
    }
}

#Preview("OverlayView") {
    OverlayView(state: TimerState(), bgImage: nil, hasPermission: true)
}

#Preview("CrackedGlassView") {
    CrackedGlassView()
}
