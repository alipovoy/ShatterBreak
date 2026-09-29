import CoreGraphics

/// Crops a break's freeze-frame to a display that changed shape mid-break, which
/// ``FrostedCaptureView`` would otherwise stretch (issue #67).
enum FreezeFrame {
    /// The centred region of the capture with the display's proportions. Only the ratio
    /// matters, so points and pixels compare.
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

    /// `capture` itself when the proportions already agree.
    static func fitted(_ capture: CGImage, to displaySize: CGSize) -> CGImage {
        let captureSize = CGSize(width: capture.width, height: capture.height)
        let rect = cropRect(captureSize: captureSize, displaySize: displaySize)

        guard rect.size != captureSize else { return capture }
        return capture.cropping(to: rect) ?? capture
    }
}
