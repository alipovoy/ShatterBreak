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
@Suite("Overlay presentation view model")
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

        #expect(spy.soundPlayCount == 1)
        #expect(viewModel.shakeOffset == 0)
        #expect(presentation.phase == .plain)
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

        #expect(spy.soundPlayCount == 0)
        #expect(presentation.phase == .plain)
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

        #expect(presentation.phase == .shattered)
        #expect(viewModel.shakeOffset == 0)
        #expect(spy.soundPlayCount == 1)
        #expect(spy.sleepDurations.isEmpty)
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

        #expect(spy.sleepDurations == [.milliseconds(900)])
        #expect(presentation.phase == .shattered)
        #expect(viewModel.shakeOffset == 0)
        #expect(spy.soundPlayCount == 1)
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

        #expect(presentation.phase == .shatterIntro)
        #expect(viewModel.shakeOffset == 10)
        #expect(spy.soundPlayCount == 0)
    }
}
