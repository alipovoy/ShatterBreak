import AppKit
import Testing

@testable import ShatterBreak

@Suite("Overlay presentation state", .tags(.overlays), .timeLimit(.minutes(1)))
struct OverlayPresentationStateTests {
    @Test("shatter upgrade advances through intro once")
    @MainActor
    func shatterUpgradeTransitionsOnce() throws {
        let state = OverlayPresentationState(
            effectType: .shatter
        )
        let firstImage = try #require(makeTestImage(width: 1))
        let secondImage = try #require(makeTestImage(width: 2))

        state.startShatter(with: firstImage)
        #expect(state.phase == .shatterIntro, "Starting shatter should enter the intro phase.")
        #expect(
            state.backgroundImage?.width == firstImage.width,
            "The first screenshot should be retained for the shatter effect."
        )

        state.startShatter(with: secondImage)
        #expect(
            state.backgroundImage?.width == firstImage.width,
            "A second shatter start should not replace the captured screenshot."
        )

        state.finishShatterIntro()
        #expect(state.phase == .shattered, "Finishing the intro should advance to the shattered phase.")
    }

    @Test("dimmed overlay ignores captured screenshots", arguments: [EffectType.dimmed, .fogged])
    @MainActor
    func nonShatterOverlayIgnoresCapture(effectType: EffectType) throws {
        let state = OverlayPresentationState(
            effectType: effectType
        )
        let image = try #require(makeTestImage(width: 1))

        state.startShatter(with: image)

        #expect(state.phase == .plain, "Non-shatter overlays should stay in the plain phase.")
        #expect(state.backgroundImage == nil, "Non-shatter overlays should ignore captured screenshots.")
        #expect(state.isShatterEffect == false, "Only the shatter effect captures and fractures the screen.")
    }

    @Test("the fogged effect always shows cracks; the dimmed effect never does")
    @MainActor
    func cracksDependOnEffect() {
        #expect(
            OverlayPresentationState(effectType: .fogged).showsCracks,
            "Fogged glass is cracked from the moment it appears."
        )
        #expect(
            OverlayPresentationState(effectType: .dimmed).showsCracks == false,
            "The dimmed effect is a plain overlay with no cracks."
        )
    }

    @Test("shatter effect still transitions without a screenshot")
    @MainActor
    func shatterWithoutScreenshotStillTransitions() {
        let state = OverlayPresentationState(
            effectType: .shatter
        )

        state.startShatter(with: nil)

        #expect(state.phase == .shatterIntro, "Shatter should enter the intro phase even without a screenshot.")
        #expect(state.backgroundImage == nil, "Missing screenshots should leave the background image empty.")

        state.finishShatterIntro()
        #expect(state.phase == .shattered, "Finishing the intro should enter the shattered phase.")
        #expect(state.showsCracks, "The shattered phase should display cracks.")
    }

    @Test("shatter intro skips motion when Reduce Motion is enabled")
    func shatterIntroSkipsMotionWhenReduceMotionIsEnabled() {
        let action = OverlayPhaseAction.resolve(
            phase: .shatterIntro,
            isShatterEffect: true,
            reduceMotion: true,
            playSoundEnabled: true,
            hasPlayedSound: false
        )

        #expect(
            action == .finishShatterIntro(playSound: true),
            "Reduce Motion should skip directly to the finished shatter state."
        )
    }

    @Test("shatter intro can skip motion without replaying sound")
    func shatterIntroSkipMotionRespectsPlayedSoundState() {
        let action = OverlayPhaseAction.resolve(
            phase: .shatterIntro,
            isShatterEffect: true,
            reduceMotion: true,
            playSoundEnabled: true,
            hasPlayedSound: true
        )

        #expect(
            action == .finishShatterIntro(playSound: false),
            "Skipping motion should not replay a sound that already played."
        )
    }

    @Test("shatter intro still animates when Reduce Motion is disabled")
    func shatterIntroStillAnimatesWithoutReduceMotion() {
        let action = OverlayPhaseAction.resolve(
            phase: .shatterIntro,
            isShatterEffect: true,
            reduceMotion: false,
            playSoundEnabled: true,
            hasPlayedSound: false
        )

        #expect(action == .animateShatterIntro, "Without Reduce Motion, shatter intro should animate.")
    }

    private func makeTestImage(width: Int) -> CGImage? {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }
}
