import SwiftUI
import AppKit

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var hasPlayedSound = false
    @State private var shakeOffset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(PreferenceKeys.playSound) private var playSound: Bool = true
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone: Bool = false

    var body: some View {
        ZStack {
            OverlayBackgroundView(
                isShatterEffect: presentation.isShatterEffect,
                backgroundImage: presentation.backgroundImage,
                phase: presentation.phase,
                shakeOffset: shakeOffset
            )

            if presentation.showsCracks {
                CrackedGlassView()
            }

            if showsForegroundContent {
                VStack(spacing: 24) {
                    Text("Time to rest")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 5)

                    CountdownTextView(state: state)
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

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    private func handlePresentationPhase() async {
        switch OverlayPhaseAction.resolve(
            phase: presentation.phase,
            isShatterEffect: presentation.isShatterEffect,
            reduceMotion: accessibilityReduceMotion,
            playSoundEnabled: playSound,
            hasPlayedSound: hasPlayedSound
        ) {
        case .idle:
            shakeOffset = 0
        case .playSound:
            shakeOffset = 0
            playGlassSoundIfNeeded()
        case .finishShatterIntro(let playSound):
            completeShatterIntro(playSound: playSound)
        case .animateShatterIntro:
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
            completeShatterIntro(playSound: true)
        }
    }

    private func completeShatterIntro(playSound: Bool) {
        shakeOffset = 0
        presentation.finishShatterIntro()
        if playSound {
            playGlassSoundIfNeeded()
        }
    }

    private func playGlassSoundIfNeeded() {
        guard playSound, hasPlayedSound == false else { return }
        hasPlayedSound = true
        NSSound(named: "Glass")?.play()
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

