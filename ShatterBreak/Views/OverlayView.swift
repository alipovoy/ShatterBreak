import AppKit
import SwiftUI

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var shakeOffset: CGFloat = 0
    @State private var hasPlayedSound = false
    @State private var hasAppeared = false

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(PreferenceKeys.playSound) private var playSound = PreferenceDefaults.playSound

    private enum Shake {
        static let distance: CGFloat = 10
        static let duration = 0.05
        static let repeatCount = 20
        static let introDelay: Duration = .milliseconds(900)
    }

    private enum Intro {
        static let fadeDuration = 0.45
    }

    var body: some View {
        ZStack {
            OverlayBackgroundView(
                effectType: presentation.effectType,
                backgroundImage: presentation.backgroundImage,
                phase: presentation.phase,
                shakeOffset: shakeOffset
            )

            if presentation.showsCracks {
                CrackedGlassView()
            }

            if showsForegroundContent {
                // One clock for the whole break screen: the buttons' windows open and close
                // as the break elapses, so they re-evaluate on the text's cadence.
                CountdownClock(state: state) { referenceDate in
                    VStack(spacing: 24) {
                        Text(.timeToRest)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 5)

                        CountdownLabel(state: state, at: referenceDate)
                            .font(.system(size: 80, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 5)

                        if state.showsPostponeButton(at: referenceDate) {
                            Button {
                                state.postpone()
                            } label: {
                                Text(.postpone)
                            }
                            .buttonStyle(OverlayActionButtonStyle())
                        }

                        if state.showsReturnButton(at: referenceDate) {
                            Button {
                                state.returnToWork()
                            } label: {
                                Text(.imBack)
                            }
                            .buttonStyle(OverlayActionButtonStyle())
                        }
                    }
                }
            }
        }
        .opacity(introOpacity)
        .animation(.easeOut(duration: Intro.fadeDuration), value: hasAppeared)
        .task(id: presentation.phase) {
            await handlePhase()
        }
        .onAppear { hasAppeared = true }
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    /// Shatter stages its own entrance through the shake-and-crack sequence, so it appears
    /// at full opacity; the other effects fade in rather than snapping on.
    private var introOpacity: Double {
        guard presentation.isShatterEffect == false else { return 1 }
        return hasAppeared ? 1 : 0
    }

    /// Plays the break sound and, for shatter, runs the shake intro before settling. The
    /// branching decision lives in the tested ``OverlayPhaseAction/resolve``.
    private func handlePhase() async {
        switch OverlayPhaseAction.resolve(
            phase: presentation.phase,
            isShatterEffect: presentation.isShatterEffect,
            reduceMotion: accessibilityReduceMotion,
            shouldPlaySound: playSound && hasPlayedSound == false,
            isSettled: presentation.settled
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

/// A break overlay over a rendered stand-in wallpaper, rasterised so the shatter effect has
/// a real capture to frost and the buttons sit over actual frosted glass.
///
/// Nothing schedules the plan, so no transition fires — though a live phase still counts
/// down, the clock being derived from the plan and the real moment.
@MainActor
private func previewOverlay(phase: TimerPlan.Phase, duration: TimeInterval = 300) -> some View {
    let presentation = OverlayPresentationState(effectType: .shatter)
    presentation.backgroundImage = ImageRenderer(content: PreviewWallpaper()).cgImage
    presentation.phase = .shattered

    // A volatile store, so the canvas neither reads nor writes real preferences. Postpone
    // has to be allowed for the resting overlay to offer it, and the break stays short so
    // the button's opening window is still open.
    let defaults = InMemoryKeyValueStore()
    defaults.set(true, forKey: PreferenceKeys.allowPostpone)
    let state = TimerState(
        overlays: .disabled,
        defaults: defaults,
        showing: .starting(phase, duration: duration)
    )
    state.restDurationSecs = duration

    return OverlayView(state: state, presentation: presentation)
        .frame(width: 480, height: 320)
}

#Preview("Resting Over Frosted Wallpaper") { @MainActor in
    previewOverlay(phase: .rest, duration: 30)
}

#Preview("Awaiting Return Over Frosted Wallpaper") { @MainActor in
    previewOverlay(phase: .awaitingReturn)
}
