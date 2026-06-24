import SwiftUI
import Testing

@testable import ShatterBreak

@Suite("CrackedGlassGenerator", .tags(.overlays))
struct CrackedGlassGeneratorTests {
    private let generator = CrackedGlassGenerator()

    @Test("returns nil for a zero-area size")
    func zeroSizeReturnsNil() {
        var rng = SeededRandomNumberGenerator(seed: 1)

        #expect(generator.generate(size: .zero, using: &rng) == nil)
        #expect(generator.generate(size: CGSize(width: 100, height: 0), using: &rng) == nil)
        #expect(generator.generate(size: CGSize(width: 0, height: 100), using: &rng) == nil)
    }

    @Test("produces non-empty geometry for a positive size")
    func positiveSizeProducesGeometry() throws {
        var rng = SeededRandomNumberGenerator(seed: 1)

        let glass = try #require(generator.generate(size: CGSize(width: 400, height: 300), using: &rng))

        #expect(glass.mainCracks.isEmpty == false)
    }

    @Test("the same seed yields identical geometry")
    func sameSeedIsDeterministic() {
        var first = SeededRandomNumberGenerator(seed: 42)
        var second = SeededRandomNumberGenerator(seed: 42)

        let size = CGSize(width: 400, height: 300)
        let firstGlass = generator.generate(size: size, using: &first)
        let secondGlass = generator.generate(size: size, using: &second)

        #expect(firstGlass == secondGlass)
    }

    @Test("different seeds yield different geometry")
    func differentSeedsDiffer() {
        var first = SeededRandomNumberGenerator(seed: 1)
        var second = SeededRandomNumberGenerator(seed: 2)

        let size = CGSize(width: 400, height: 300)
        let firstGlass = generator.generate(size: size, using: &first)
        let secondGlass = generator.generate(size: size, using: &second)

        #expect(firstGlass != secondGlass)
    }

    @Test("the impact point is offset from center but stays on screen")
    func impactPointOffsetButOnScreen() throws {
        var rng = SeededRandomNumberGenerator(seed: 7)

        let size = CGSize(width: 400, height: 300)
        let glass = try #require(generator.generate(size: size, using: &rng))

        // The impact is jittered by up to 35% of each axis, so it lands off-center
        // while remaining within the display bounds.
        #expect(abs(glass.shatterCenter.x - size.width * 0.5) <= size.width * 0.35)
        #expect(abs(glass.shatterCenter.y - size.height * 0.5) <= size.height * 0.35)
        #expect((0...size.width).contains(glass.shatterCenter.x))
        #expect((0...size.height).contains(glass.shatterCenter.y))
    }
}
