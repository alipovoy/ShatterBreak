import Testing

@testable import ShatterBreak

/// Shatter captures the screen only with both consents settled; anything less falls back to
/// fogged rather than a capture that would put a system dialog over the break (issue #90).
@Suite("Effect resolution", .tags(.overlays))
struct EffectResolutionTests {
    @Test(
        "shatter needs Screen Recording and an allowed direct capture",
        arguments: [
            (true, DirectCaptureAccess.allowed, EffectType.shatter),
            (false, .allowed, .fogged),
            (true, .unknown, .fogged),
            (true, .refused, .fogged)
        ]
    )
    func shatter(recording: Bool, direct: DirectCaptureAccess, expected: EffectType) {
        let resolved = OverlayManager.resolveEffectType(
            selected: .shatter,
            hasScreenRecordingPermission: recording,
            directCaptureAccess: direct
        )
        #expect(resolved == expected)
    }

    @Test("fogged and dimmed never depend on consent", arguments: [EffectType.fogged, .dimmed])
    func permissionless(selected: EffectType) {
        let resolved = OverlayManager.resolveEffectType(
            selected: selected,
            hasScreenRecordingPermission: false,
            directCaptureAccess: .refused
        )
        #expect(resolved == selected)
    }
}
