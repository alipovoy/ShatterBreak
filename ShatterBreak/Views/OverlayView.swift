import AppKit
import SwiftUI

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var shakeOffset: CGFloat = 0
    @State private var hasPlayedSound = false

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone = PreferenceDefaults.allowPostpone

    private enum Shake {
        static let distance: CGFloat = 10
        static let duration = 0.05
        static let repeatCount = 20
        static let introDelay: Duration = .milliseconds(900)
    }

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
                    Text(.timeToRest)
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
                            Text(.postpone)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        // The overlay is a borderless, non-key window, so the prominent
                        // style renders its fill in AppKit's inactive grey. Drawing the
                        // capsule explicitly keeps the accent color regardless of key state.
                        .background(Color.accentColor, in: Capsule())
                    }

                    if state.awaitingReturn {
                        Button {
                            state.start()
                        } label: {
                            Text(.imBack)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        // The overlay is a borderless, non-key window, so the prominent
                        // style renders its fill in AppKit's inactive grey. Drawing the
                        // capsule explicitly keeps the accent color regardless of key state.
                        .background(Color.accentColor, in: Capsule())
                    }
                }
            }
        }
        .task(id: presentation.phase) {
            await handlePhase()
        }
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    /// Reacts to the current overlay phase: plays the break sound, and for the shatter
    /// effect runs the shake intro before settling into the shattered state. The
    /// branching decision lives in the pure, tested ``OverlayPhaseAction/resolve``.
    private func handlePhase() async {
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
        case .finishShatterIntro(let playGlass):
            finishShatterIntro(playGlass: playGlass)
        case .animateShatterIntro:
            await animateShatterIntro()
        }
    }

    private func animateShatterIntro() async {
        shakeOffset = 0
        withAnimation(
            .spring(duration: Shake.duration)
            .repeatCount(Shake.repeatCount, autoreverses: true)
        ) {
            shakeOffset = Shake.distance
        }

        do {
            try await Task.sleep(for: Shake.introDelay)
            try Task.checkCancellation()
        } catch {
            return
        }

        guard presentation.phase == .shatterIntro else { return }
        finishShatterIntro(playGlass: true)
    }

    private func finishShatterIntro(playGlass: Bool) {
        shakeOffset = 0
        presentation.finishShatterIntro()
        if playGlass {
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
