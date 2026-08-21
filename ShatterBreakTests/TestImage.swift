import CoreGraphics
import Testing

/// Builds throwaway bitmaps for tests that need a real ``CGImage``. The freeze-frame
/// pipeline carries captures around by reference and fits them by their dimensions,
/// so both identity and size are what tests assert against.
enum TestImage {
    static func make(width: Int = 1, height: Int = 1) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            "A \(width)x\(height) RGBA bitmap context should always be creatable."
        )

        return try #require(context.makeImage(), "The bitmap context should produce a CGImage.")
    }
}
