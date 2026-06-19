import AppKit
import SwiftUI

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var viewModel = OverlayPresentationViewModel()

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(PreferenceKeys.playSound) private var playSound: Bool = true
    @AppStorage(PreferenceKeys.allowPostpone) private var allowPostpone: Bool = false

    var body: some View {
        ZStack {
            OverlayBackgroundView(
                isShatterEffect: presentation.isShatterEffect,
                backgroundImage: presentation.backgroundImage,
                phase: presentation.phase,
                shakeOffset: viewModel.shakeOffset
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
            await viewModel.handlePresentationPhase(
                presentation: presentation,
                reduceMotion: accessibilityReduceMotion,
                playSoundEnabled: playSound
            )
        }
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
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
