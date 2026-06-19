import CoreGraphics
import Foundation
import Testing

@testable import ShatterBreak

@Suite("OverlayManager capture pipeline", .tags(.overlays))
@MainActor
struct OverlayManagerCaptureTests {
    private let primaryDisplay: CGDirectDisplayID = 1
    private let secondaryDisplay: CGDirectDisplayID = 2

    @Test("a matching session paints captured images onto their displays")
    func matchingSessionAppliesImages() throws {
        let session = UUID()
        let states = makeOverlayStates()
        let image = try makeCGImage()

        OverlayManager.applyCapturedImages(
            [primaryDisplay: image, secondaryDisplay: image],
            sessionID: session,
            activeSessionID: session,
            to: states
        )

        for state in states.values {
            #expect(state.phase == .shatterIntro, "Each display should advance to the shatter intro.")
            #expect(state.backgroundImage != nil, "Each display should receive its captured screenshot.")
        }
    }

    @Test("a display missing from the capture falls back to a plain shatter")
    func partialCaptureFallsBackPerDisplay() throws {
        let session = UUID()
        let states = makeOverlayStates()
        let image = try makeCGImage()

        OverlayManager.applyCapturedImages(
            [primaryDisplay: image],
            sessionID: session,
            activeSessionID: session,
            to: states
        )

        #expect(states[primaryDisplay]?.backgroundImage != nil, "The captured display keeps its screenshot.")
        #expect(states[primaryDisplay]?.phase == .shatterIntro)
        #expect(states[secondaryDisplay]?.backgroundImage == nil, "The failed display falls back to no screenshot.")
        #expect(
            states[secondaryDisplay]?.phase == .shatterIntro,
            "A display without a screenshot still shatters, just without a freeze-frame."
        )
    }

    @Test("a total capture failure still shatters every display without a screenshot")
    func totalCaptureFailureShattersWithoutImages() {
        let session = UUID()
        let states = makeOverlayStates()

        OverlayManager.applyCapturedImages(
            [:],
            sessionID: session,
            activeSessionID: session,
            to: states
        )

        for state in states.values {
            #expect(state.phase == .shatterIntro, "An empty capture should still trigger the shatter.")
            #expect(state.backgroundImage == nil, "An empty capture leaves displays without a freeze-frame.")
        }
    }

    @Test("a stale capture is dropped once the session has rotated")
    func staleSessionCaptureIsDropped() throws {
        let captureSession = UUID()
        let activeSession = UUID()
        let states = makeOverlayStates()
        let image = try makeCGImage()

        OverlayManager.applyCapturedImages(
            [primaryDisplay: image, secondaryDisplay: image],
            sessionID: captureSession,
            activeSessionID: activeSession,
            to: states
        )

        for state in states.values {
            #expect(state.phase == .plain, "A capture from a rotated session must not paint later overlays.")
            #expect(state.backgroundImage == nil, "A stale capture must not leak its screenshot onto new windows.")
        }
    }

    // MARK: - Helpers

    private func makeOverlayStates() -> [CGDirectDisplayID: OverlayPresentationState] {
        [
            primaryDisplay: OverlayPresentationState(effectType: .shatter, allowsShatterUpgrade: true),
            secondaryDisplay: OverlayPresentationState(effectType: .shatter, allowsShatterUpgrade: true)
        ]
    }

    private func makeCGImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            "A 1x1 RGBA bitmap context should always be creatable."
        )

        return try #require(context.makeImage(), "The bitmap context should produce a CGImage.")
    }
}
