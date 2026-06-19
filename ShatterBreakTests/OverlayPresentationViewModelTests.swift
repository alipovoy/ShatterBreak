import Testing

@testable import ShatterBreak

@MainActor
private final class OverlayPresentationViewModelSpy {
    private(set) var soundPlayCount = 0
    private(set) var sleepDurations: [Duration] = []
    var sleepError: (any Error)?

    var dependencies: OverlayPresentationViewModel.Dependencies {
        .init(
            playGlassSound: { [unowned self] in
                soundPlayCount += 1
            },
            sleep: { [unowned self] duration in
                sleepDurations.append(duration)
                if let sleepError {
                    throw sleepError
                }
            }
        )
    }
}

@MainActor
@Suite("Overlay presentation view model", .tags(.overlays), .timeLimit(.minutes(1)))
struct OverlayPresentationViewModelTests {
    @Test("plain overlay plays the sound once")
    func plainOverlayPlaysSoundOnce() async {
        let spy = OverlayPresentationViewModelSpy()
        let viewModel = OverlayPresentationViewModel(dependencies: spy.dependencies)
        let presentation = OverlayPresentationState(
            effectType: .overlay,
            allowsShatterUpgrade: false
        )

        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: false,
            playSoundEnabled: true
        )
        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: false,
            playSoundEnabled: true
        )

        #expect(spy.soundPlayCount == 1, "A plain overlay should play its sound only once.")
        #expect(viewModel.shakeOffset == 0, "Plain overlays should not shake.")
        #expect(presentation.phase == .plain, "Plain overlays should remain in the plain phase.")
    }

    @Test("plain overlay respects the sound preference")
    func plainOverlayRespectsSoundPreference() async {
        let spy = OverlayPresentationViewModelSpy()
        let viewModel = OverlayPresentationViewModel(dependencies: spy.dependencies)
        let presentation = OverlayPresentationState(
            effectType: .overlay,
            allowsShatterUpgrade: false
        )

        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: false,
            playSoundEnabled: false
        )

        #expect(spy.soundPlayCount == 0, "Disabled sound preference should prevent playback.")
        #expect(presentation.phase == .plain, "Sound preference should not alter the plain overlay phase.")
    }

    @Test("Reduce Motion finishes shatter intro without shaking")
    func reduceMotionFinishesShatterIntroWithoutShaking() async {
        let spy = OverlayPresentationViewModelSpy()
        let viewModel = OverlayPresentationViewModel(dependencies: spy.dependencies)
        let presentation = OverlayPresentationState(
            effectType: .shatter,
            allowsShatterUpgrade: false
        )
        presentation.startShatter(with: nil)

        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: true,
            playSoundEnabled: true
        )

        #expect(presentation.phase == .shattered, "Reduce Motion should finish the shatter intro immediately.")
        #expect(viewModel.shakeOffset == 0, "Reduce Motion should avoid shake offset.")
        #expect(spy.soundPlayCount == 1, "Finishing the shatter intro should play the sound once.")
        #expect(spy.sleepDurations.isEmpty, "Reduce Motion should skip the shatter animation delay.")
    }

    @Test("animated shatter intro waits before finishing")
    func animatedShatterIntroWaitsBeforeFinishing() async {
        let spy = OverlayPresentationViewModelSpy()
        let viewModel = OverlayPresentationViewModel(dependencies: spy.dependencies)
        let presentation = OverlayPresentationState(
            effectType: .shatter,
            allowsShatterUpgrade: false
        )
        presentation.startShatter(with: nil)

        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: false,
            playSoundEnabled: true
        )

        #expect(spy.sleepDurations == [.milliseconds(900)], "Animated shatter should wait for the intro duration.")
        #expect(presentation.phase == .shattered, "Animated shatter should finish after the intro delay.")
        #expect(viewModel.shakeOffset == 0, "Shake offset should reset after the intro finishes.")
        #expect(spy.soundPlayCount == 1, "Animated shatter should play the sound once.")
    }

    @Test("cancelled shatter intro leaves the phase unchanged")
    func cancelledShatterIntroLeavesPhaseUnchanged() async {
        let spy = OverlayPresentationViewModelSpy()
        spy.sleepError = CancellationError()
        let viewModel = OverlayPresentationViewModel(dependencies: spy.dependencies)
        let presentation = OverlayPresentationState(
            effectType: .shatter,
            allowsShatterUpgrade: false
        )
        presentation.startShatter(with: nil)

        await viewModel.handlePresentationPhase(
            presentation: presentation,
            reduceMotion: false,
            playSoundEnabled: true
        )

        #expect(presentation.phase == .shatterIntro, "Cancellation should leave the shatter intro in progress.")
        #expect(viewModel.shakeOffset == 10, "Cancellation should preserve the in-progress shake offset.")
        #expect(spy.soundPlayCount == 0, "Cancellation should prevent finishing sound playback.")
    }
}
