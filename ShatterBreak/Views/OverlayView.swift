import SwiftUI
import AppKit

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var hasPlayedSound = false
    @State private var shakeOffset: CGFloat = 0

    @AppStorage(PreferenceKeys.playSound) private var playSound: Bool = true
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone: Bool = false

    var body: some View {
        ZStack {
            backgroundLayer

            if presentation.showsCracks {
                CrackedGlassView()
            }

            if showsForegroundContent {
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
        .task(id: presentation.phase) {
            await handlePresentationPhase()
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        backgroundSurface
            .offset(
                x: presentation.phase == .shatterIntro ? shakeOffset : 0,
                y: presentation.phase == .shatterIntro ? -shakeOffset : 0
            )
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        if presentation.isShatterEffect {
            if let cgImage = presentation.backgroundImage,
               presentation.phase != .plain {
                Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    .resizable()
            } else if presentation.phase == .plain {
                Color.clear
            } else {
                Color.black.opacity(0.85)
            }
        } else {
            Color.black.opacity(0.85)
        }
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    private func handlePresentationPhase() async {
        switch presentation.phase {
        case .plain:
            shakeOffset = 0
            if playSound, presentation.isShatterEffect == false, hasPlayedSound == false {
                hasPlayedSound = true
                NSSound(named: "Glass")?.play()
            }
        case .shatterIntro:
            shakeOffset = 0

            withAnimation(.spring(duration: 0.05).repeatCount(20, autoreverses: true)) {
                shakeOffset = 10
            }

            do {
                try await Task.sleep(for: .milliseconds(900))
                try Task.checkCancellation()
            } catch {
                return
            }

            guard presentation.phase == .shatterIntro else { return }
            shakeOffset = 0
            presentation.finishShatterIntro()

            if playSound, hasPlayedSound == false {
                hasPlayedSound = true
                NSSound(named: "Glass")?.play()
            }
        case .shattered:
            shakeOffset = 0
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        TimerState.format(timeInterval: interval)
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
        OverlayView(
            state: restingState,
            presentation: OverlayPresentationState(
                effectType: .overlay,
                allowsShatterUpgrade: false
            )
        )
            .frame(width: 400, height: 300)
            .padding()

        OverlayView(
            state: awaitingState,
            presentation: OverlayPresentationState(
                effectType: .overlay,
                allowsShatterUpgrade: false
            )
        )
            .frame(width: 400, height: 300)
            .padding()
    }
}


#Preview("CrackedGlassView") {
    CrackedGlassView()
}
