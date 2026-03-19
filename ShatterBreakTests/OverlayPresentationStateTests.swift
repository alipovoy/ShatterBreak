import AppKit
import Testing

@testable import ShatterBreak

@Suite("Overlay presentation state")
struct OverlayPresentationStateTests {
    @Test("shatter upgrade advances through intro once")
    @MainActor
    func shatterUpgradeTransitionsOnce() throws {
        let state = OverlayPresentationState(
            effectType: .shatter,
            allowsShatterUpgrade: true
        )
        let firstImage = try #require(makeTestImage(width: 1))
        let secondImage = try #require(makeTestImage(width: 2))

        state.startShatter(with: firstImage)
        #expect(state.phase == .shatterIntro)
        #expect(state.backgroundImage?.width == firstImage.width)

        state.startShatter(with: secondImage)
        #expect(state.backgroundImage?.width == firstImage.width)

        state.finishShatterIntro()
        #expect(state.phase == .shattered)
    }

    @Test("plain overlay ignores captured screenshots")
    @MainActor
    func plainOverlayIgnoresCapture() throws {
        let state = OverlayPresentationState(
            effectType: .overlay,
            allowsShatterUpgrade: false
        )
        let image = try #require(makeTestImage(width: 1))

        state.startShatter(with: image)

        #expect(state.phase == .plain)
        #expect(state.backgroundImage == nil)
    }

    @Test("shatter effect still transitions without a screenshot")
    @MainActor
    func shatterWithoutScreenshotStillTransitions() {
        let state = OverlayPresentationState(
            effectType: .shatter,
            allowsShatterUpgrade: false
        )

        state.startShatter(with: nil)

        #expect(state.phase == .shatterIntro)
        #expect(state.backgroundImage == nil)

        state.finishShatterIntro()
        #expect(state.phase == .shattered)
        #expect(state.showsCracks)
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

        #expect(action == .finishShatterIntro(playSound: true))
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

        #expect(action == .finishShatterIntro(playSound: false))
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

        #expect(action == .animateShatterIntro)
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
