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
    @AppStorage(PreferenceKeys.reduceMotion) private var reduceMotion = PreferenceDefaults.reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 80

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
                // One clock for the whole screen: the buttons' windows open and close with it.
                CountdownClock(state: state) { referenceDate in
                    VStack(spacing: 24) {
                        Text(.timeToRest)
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 5)

                        CountdownLabel(state: state, at: referenceDate)
                            .font(.system(size: countdownFontSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 5)
                            .accessibilityLabel(accessibleRemaining(at: referenceDate))
                    }
                    // Hung below the title and timer without taking part in their layout,
                    // so the timer stays centred whether or not buttons are showing.
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 24) {
                            if state.showsPostponeButton(at: referenceDate) {
                                Button {
                                    state.postpone()
                                } label: {
                                    Text(.postpone)
                                }
                                .buttonStyle(OverlayActionButtonStyle())
                                .accessibilityHint(Text(.postponeAccessibilityHint))
                            }

                            if state.showsReturnButton(at: referenceDate) {
                                Button {
                                    state.returnToWork()
                                } label: {
                                    Text(.imBack)
                                }
                                .buttonStyle(OverlayActionButtonStyle())
                                .accessibilityHint(Text(.imBackAccessibilityHint))
                            }
                        }
                        .alignmentGuide(.bottom) { $0[.top] - 24 }
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

    /// Spoken form of the countdown for VoiceOver, since "24:31" reads as digits and a colon.
    private func accessibleRemaining(at referenceDate: Date) -> String {
        Duration.seconds(state.timeRemaining(at: referenceDate))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    private var isMotionReduced: Bool {
        reduceMotion || accessibilityReduceMotion
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    /// Shatter stages its own entrance, unless motion is reduced; then it fades in like the others.
    private var introOpacity: Double {
        guard presentation.isShatterEffect == false || isMotionReduced else { return 1 }
        return hasAppeared ? 1 : 0
    }

    private func handlePhase() async {
        switch OverlayPhaseAction.resolve(
            phase: presentation.phase,
            isShatterEffect: presentation.isShatterEffect,
            reduceMotion: isMotionReduced,
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

/// Over a stand-in wallpaper, so the shatter effect has a capture to frost.
@MainActor
private func previewOverlay(phase: TimerPlan.Phase, duration: TimeInterval = 300) -> some View {
    let presentation = OverlayPresentationState(effectType: .shatter)
    presentation.backgroundImage = PreviewWallpaper.image
    presentation.phase = .shattered

    // Postpone must be allowed for the overlay to offer it.
    let defaults = InMemoryKeyValueStore()
    defaults.set(true, forKey: PreferenceKeys.allowPostpone)
    let state = TimerState.parked(.starting(phase, duration: duration), defaults: defaults)
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
