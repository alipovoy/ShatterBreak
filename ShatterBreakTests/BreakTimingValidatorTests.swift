import Testing

@testable import ShatterBreak

@Suite("BreakTimingValidator warnings")
struct BreakTimingValidatorTests {
    private func warnings(
        rest: Double,
        allowPostpone: Bool = true,
        postponeWindow: Double,
        allowEarlyReturn: Bool = true,
        earlyReturnLead: Double
    ) -> [BreakTimingWarning] {
        BreakTimingValidator.warnings(
            restDurationSecs: rest,
            allowPostpone: allowPostpone,
            postponeWindowSecs: postponeWindow,
            allowEarlyReturn: allowEarlyReturn,
            earlyReturnLeadSecs: earlyReturnLead
        )
    }

    @Test("No warnings when both windows fit and leave a rest gap")
    func noWarningsWhenWindowsFit() {
        #expect(warnings(rest: 300, postponeWindow: 60, earlyReturnLead: 30).isEmpty)
    }

    @Test("Disabled features never warn, even when their value would exceed the break")
    func disabledFeaturesDoNotWarn() {
        let result = warnings(
            rest: 10,
            allowPostpone: false,
            postponeWindow: 600,
            allowEarlyReturn: false,
            earlyReturnLead: 600
        )
        #expect(result.isEmpty)
    }

    @Test("Postpone window longer than the break warns")
    func postponeWindowExceeds() {
        let result = warnings(rest: 10, postponeWindow: 20, allowEarlyReturn: false, earlyReturnLead: 0)
        #expect(result == [.postponeWindowExceedsRest])
    }

    @Test("Early-return lead longer than the break warns")
    func earlyReturnLeadExceeds() {
        let result = warnings(rest: 10, allowPostpone: false, postponeWindow: 0, earlyReturnLead: 20)
        #expect(result == [.earlyReturnLeadExceedsRest])
    }

    @Test("A window exactly equal to the break is a valid exact fit")
    func windowEqualToRestIsValid() {
        let result = warnings(rest: 10, postponeWindow: 10, allowEarlyReturn: false, earlyReturnLead: 0)
        #expect(result.isEmpty)
    }

    @Test("Crossing the break length by a step triggers the exceeds warning")
    func windowJustOverRestWarns() {
        let result = warnings(rest: 10, postponeWindow: 15, allowEarlyReturn: false, earlyReturnLead: 0)
        #expect(result == [.postponeWindowExceedsRest])
    }

    @Test("Overlap warns only when the windows sum past the break")
    func overlapEdgeCases() {
        // Just over -> overlap.
        #expect(warnings(rest: 10, postponeWindow: 6, earlyReturnLead: 5) == [.windowsOverlap])
        // Exactly meeting -> no gap but no overlap.
        #expect(warnings(rest: 10, postponeWindow: 6, earlyReturnLead: 4).isEmpty)
        // Comfortably under -> no overlap.
        #expect(warnings(rest: 10, postponeWindow: 6, earlyReturnLead: 3).isEmpty)
    }

    @Test("Overlap is suppressed when an exceeds warning already covers the collision")
    func overlapSuppressedWhenAWindowExceeds() {
        let result = warnings(rest: 10, postponeWindow: 20, earlyReturnLead: 5)
        #expect(result == [.postponeWindowExceedsRest])
    }

    @Test("Both windows exceeding the break warn individually, without an overlap entry")
    func bothExceedWarnSeparately() {
        let result = warnings(rest: 10, postponeWindow: 20, earlyReturnLead: 20)
        #expect(result == [.postponeWindowExceedsRest, .earlyReturnLeadExceedsRest])
    }
}
