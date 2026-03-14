import SwiftUI
import AppKit

struct OverlayView: View {
    @Bindable var state: TimerState
    var bgImage: CGImage?
    var hasPermission: Bool

    @State private var phase = 0
    @State private var shakeOffset: CGFloat = 0

    @AppStorage(PreferenceKeys.playSound) private var playSound: Bool = true
    @AppStorage(PreferenceKeys.effectType) private var effectType: EffectType = .shatter
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone: Bool = false

    var body: some View {
        ZStack {
            backgroundLayer

            if phase == 2 || (!hasPermission && phase > 0) {
                CrackedGlassView()

                VStack(spacing: 24) {
                    Text("Time to rest")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 5)

                    Text(formattedTime(state.timeRemaining))
                        .font(.system(size: 80, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 5)

                    if state.canPostpone && allowPostpone {
                        Button {
                            state.postpone()
                        } label: {
                            Text("Postpone")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .background(Color.accentColor, in: Capsule())
                    }

                    if state.awaitingReturn {
                        Button {
                            state.start()
                        } label: {
                            Text("I'm back")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .background(Color.accentColor, in: Capsule())
                    }
                }
            }
        }
        .task {
            await runAnimationSequence()
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if effectType == .shatter, hasPermission, let cgImage = bgImage {
            Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                .resizable()
                .offset(x: phase == 1 ? shakeOffset : 0, y: phase == 1 ? -shakeOffset : 0)
        } else {
            Color.black.opacity(0.85)
        }
    }

    private func runAnimationSequence() async {
        if effectType == .shatter && hasPermission {
            if Task.isCancelled { return }

            phase = 1
            withAnimation(Animation.spring(duration: 0.05).repeatCount(20, autoreverses: true)) {
                shakeOffset = 10
            }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(900))
        }
        phase = 2

        if playSound {
            NSSound(named: "Glass")?.play()
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        let minutesPadded = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let secondsPadded = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutesPadded):\(secondsPadded)"
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
                guard isGenerated else { return }

                context.stroke(mainCracks, with: .color(.black.opacity(0.5)), lineWidth: 3)
                context.stroke(webCracks,  with: .color(.black.opacity(0.3)), lineWidth: 1.5)

                context.stroke(mainCracks, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                context.stroke(webCracks,  with: .color(.white.opacity(0.6)), lineWidth: 0.5)

                let impactRect = CGRect(x: shatterCenter.x - 5, y: shatterCenter.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: impactRect), with: .color(.white.opacity(0.9)))
            }
            .task(id: geometry.size) {
                // This runs on MainActor inheriting from view context
                // Handles both initial appearance and size changes
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

        self.shatterCenter = center
        self.mainCracks = main
        self.webCracks = web
        self.isGenerated = true
    }
}

#Preview("OverlayView") { @MainActor in
    struct WindowConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            Task { @MainActor in
                guard let window = view.window else { return }
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    // show resting state
    let restingState = TimerState()
    restingState.mode = .resting

    // show awaiting-return state
    let awaitingState = TimerState()
    awaitingState.mode = .awaitingReturn

    return VStack {
        OverlayView(state: restingState, bgImage: nil, hasPermission: true)
            .frame(width: 400, height: 300)
            .padding()

        OverlayView(state: awaitingState, bgImage: nil, hasPermission: true)
            .frame(width: 400, height: 300)
            .padding()
    }
}


#Preview("CrackedGlassView") {
    CrackedGlassView()
}
