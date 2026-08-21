import CoreGraphics
import Testing

@testable import ShatterBreak

/// Covers the geometry behind reusing a break's freeze-frame on a display that changed
/// shape mid-break (issue #67).
@Suite("Freeze-frame fitting", .tags(.overlays))
struct FreezeFrameTests {
    private let widescreen = CGSize(width: 1920, height: 1080)

    @Test("a display keeping its proportions keeps the whole capture")
    func matchingAspectIsUncropped() {
        let rect = FreezeFrame.cropRect(captureSize: widescreen, displaySize: widescreen)

        #expect(rect == CGRect(origin: .zero, size: widescreen))
    }

    @Test("a Retina capture is measured against its display in points")
    func backingScaleIsIrrelevant() {
        let retina = CGSize(width: 3840, height: 2160)
        let rect = FreezeFrame.cropRect(captureSize: retina, displaySize: widescreen)

        #expect(
            rect == CGRect(origin: .zero, size: retina),
            "Only the ratio matters, so a 2x capture of the same display needs no crop."
        )
    }

    @Test("a capture wider than its display is cropped evenly at the sides")
    func widerCaptureCropsHorizontally() {
        let rect = FreezeFrame.cropRect(
            captureSize: widescreen,
            displaySize: CGSize(width: 1000, height: 1000)
        )

        #expect(rect == CGRect(x: 420, y: 0, width: 1080, height: 1080))
    }

    @Test("a capture taller than its display is cropped evenly top and bottom")
    func tallerCaptureCropsVertically() {
        let rect = FreezeFrame.cropRect(
            captureSize: CGSize(width: 1000, height: 1000),
            displaySize: widescreen
        )

        // 1000 / (16:9) is 562.5, rounded down so the crop always fits the capture.
        #expect(rect == CGRect(x: 0, y: 219, width: 1000, height: 562))
    }

    @Test(
        "a degenerate size leaves the capture whole",
        arguments: [CGSize.zero, CGSize(width: 1920, height: 0), CGSize(width: 0, height: 1080)]
    )
    func degenerateSizesAreUncropped(degenerate: CGSize) {
        #expect(FreezeFrame.cropRect(captureSize: widescreen, displaySize: degenerate) ==
            CGRect(origin: .zero, size: widescreen))
        #expect(FreezeFrame.cropRect(captureSize: degenerate, displaySize: widescreen) ==
            CGRect(origin: .zero, size: degenerate))
    }

    @Test("fitting hands back the very same image when no crop is needed")
    func fittedReturnsTheSameImage() throws {
        let capture = try TestImage.make(width: 160, height: 90)

        #expect(
            FreezeFrame.fitted(capture, to: widescreen) === capture,
            "A display that only moved or changed scale must keep the image it was showing."
        )
    }

    @Test("fitting crops the capture to the display's proportions")
    func fittedCropsToTheDisplay() throws {
        let capture = try TestImage.make(width: 160, height: 90)
        let fitted = FreezeFrame.fitted(capture, to: CGSize(width: 100, height: 100))

        #expect(fitted.width == 90)
        #expect(fitted.height == 90)
    }
}
