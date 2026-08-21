import CoreGraphics

/// Fits a break's freeze-frame to a display whose geometry changed mid-break.
///
/// ``FrostedCaptureView`` stretches whatever image it is given to fill its window, so
/// a screenshot taken at the display's old shape distorts once that shape changes
/// (issue #67). Cropping the retained capture to the display's new proportions keeps
/// the frozen desktop true to itself, at the cost of the edges that no longer fit.
///
/// The crop is centred and pure geometry, so it is exercised without a window server.
enum FreezeFrame {
    /// The region of a `captureSize` screenshot that shares `displaySize`'s
    /// proportions, centred so the crop takes evenly from both edges.
    ///
    /// Only the ratio of `displaySize` matters, which is why a frame measured in
    /// points can be compared against a capture measured in pixels: the display's
    /// backing scale cancels out. Degenerate or already-matching sizes yield the
    /// whole capture.
    static func cropRect(captureSize: CGSize, displaySize: CGSize) -> CGRect {
        let whole = CGRect(origin: .zero, size: captureSize)

        guard captureSize.width > 0, captureSize.height > 0,
              displaySize.width > 0, displaySize.height > 0 else { return whole }

        let captureAspect = captureSize.width / captureSize.height
        let displayAspect = displaySize.width / displaySize.height

        var cropped = captureSize
        if captureAspect > displayAspect {
            cropped.width = (captureSize.height * displayAspect).rounded(.down)
        } else if captureAspect < displayAspect {
            cropped.height = (captureSize.width / displayAspect).rounded(.down)
        } else {
            return whole
        }

        return CGRect(
            x: ((captureSize.width - cropped.width) / 2).rounded(.down),
            y: ((captureSize.height - cropped.height) / 2).rounded(.down),
            width: cropped.width,
            height: cropped.height
        )
    }

    /// `capture` cropped to `displaySize`'s proportions.
    ///
    /// Returns `capture` itself when the proportions already agree, so a display that
    /// only moved or changed scale keeps the exact image it was showing. Always pass
    /// the session's pristine capture rather than the image currently on screen:
    /// re-cropping an earlier crop would eat further into the desktop each time.
    static func fitted(_ capture: CGImage, to displaySize: CGSize) -> CGImage {
        let captureSize = CGSize(width: capture.width, height: capture.height)
        let rect = cropRect(captureSize: captureSize, displaySize: displaySize)

        guard rect.size != captureSize else { return capture }
        return capture.cropping(to: rect) ?? capture
    }
}
