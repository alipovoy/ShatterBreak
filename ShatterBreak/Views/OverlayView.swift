import AppKit
import SwiftUI

struct OverlayView: View {
    @Bindable var state: TimerState
    @Bindable var presentation: OverlayPresentationState

    @State private var shakeOffset: CGFloat = 0
    @State private var hasPlayedSound = false
    @State private var hasAppeared = false

    /// Ticks once per second while resting so the time-windowed action buttons
    /// re-evaluate their visibility as the break elapses.
    @State private var referenceDate = Date.now

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
                VStack(spacing: 24) {
                    Text(.timeToRest)
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 5)

                    CountdownTextView(state: state)
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
                            state.start()
                        } label: {
                            Text(.imBack)
                        }
                        .buttonStyle(OverlayActionButtonStyle())
                    }
                }
            }
        }
        .opacity(introOpacity)
        .animation(.easeOut(duration: Intro.fadeDuration), value: hasAppeared)
        .task(id: presentation.phase) {
            await handlePhase()
        }
        .task(id: state.mode) {
            await driveActionClock()
        }
        .onAppear { hasAppeared = true }
    }

    /// Refreshes `referenceDate` on each second boundary while the break counts down,
    /// so the Postpone and "I'm back" windows re-evaluate. Mirrors
    /// ``CountdownTextView/driveVisibleClockIfNeeded``. Awaiting-return is static, so it
    /// sets the date once and returns without looping.
    @MainActor
    private func driveActionClock() async {
        referenceDate = Date.now

        guard state.isResting else { return }

        while Task.isCancelled == false {
            let remaining = state.timeRemaining(at: referenceDate)
            guard remaining > 0 else { return }

            do {
                try await Task.sleep(for: nextRefreshDelay(for: remaining), tolerance: .milliseconds(100))
            } catch {
                return
            }

            referenceDate = Date.now
        }
    }

    private func nextRefreshDelay(for remaining: TimeInterval) -> Duration {
        let fractionalSecond = remaining - floor(remaining)
        let secondsUntilRefresh = fractionalSecond > 0 ? fractionalSecond : 1
        return .seconds(secondsUntilRefresh)
    }

    private var showsForegroundContent: Bool {
        if presentation.isShatterEffect {
            return presentation.phase == .shattered
        }

        return true
    }

    /// The overlay's opacity during its intro. The shatter effect stages its own
    /// entrance through the shake-and-crack sequence, so it appears at full opacity;
    /// the dimmed and fogged effects gently fade in instead of snapping on (issue #62).
    private var introOpacity: Double {
        guard presentation.isShatterEffect == false else { return 1 }
        return hasAppeared ? 1 : 0
    }

    /// Reacts to the current overlay phase: plays the break sound, and for the shatter
    /// effect runs the shake intro before settling into the shattered state. The
    /// branching decision lives in the pure, tested ``OverlayPhaseAction/resolve``.
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

#Preview("Over Frosted Wallpaper") { @MainActor in
    // Render the stand-in wallpaper to a CGImage so the shatter effect has a real
    // capture to frost, putting the action buttons over actual frosted glass.
    let backgroundImage = ImageRenderer(content: PreviewWallpaper()).cgImage

    let restingPresentation = OverlayPresentationState(effectType: .shatter)
    restingPresentation.backgroundImage = backgroundImage
    restingPresentation.phase = .shattered

    let awaitingPresentation = OverlayPresentationState(effectType: .shatter)
    awaitingPresentation.backgroundImage = backgroundImage
    awaitingPresentation.phase = .shattered

    // resting → Postpone button. Enable postpone and keep the break short so its
    // opening window is still active even without a running countdown.
    UserDefaults.standard.set(true, forKey: PreferenceKeys.allowPostpone)
    let restingState = TimerState()
    restingState.mode = .resting
    restingState.restDurationSecs = 30

    // awaiting return → I'm back button
    let awaitingState = TimerState()
    awaitingState.mode = .awaitingReturn

    return VStack(spacing: 0) {
        OverlayView(state: restingState, presentation: restingPresentation)
            .frame(width: 480, height: 320)

        OverlayView(state: awaitingState, presentation: awaitingPresentation)
            .frame(width: 480, height: 320)
    }
}
