import Foundation

/// A contradiction between the break-timing settings and the configured break length.
///
/// Surfaced to the user as a warning in Preferences rather than silently clamped, so
/// the behavior stays explicit.
enum BreakTimingWarning: Hashable {
    /// The Postpone window is longer than the break, so Postpone never auto-hides.
    case postponeWindowExceedsRest
    /// The early-return lead is longer than the break, so "I'm back" shows throughout.
    case earlyReturnLeadExceedsRest
    /// The Postpone and "I'm back" windows overlap, leaving no button-free rest gap.
    case windowsOverlap
}

/// Pure validation for the break-timing windows.
///
/// Kept as a stateless namespace so the warning decision is unit-testable without any
/// UI, and shared verbatim by ``BreakTimingWarningsView``. All comparisons are strictly
/// greater than rest: a window *equal* to the break, or windows that exactly meet, are
/// valid and warning-free.
enum BreakTimingValidator {
    static func warnings(
        restDurationSecs: Double,
        allowPostpone: Bool,
        postponeWindowSecs: Double,
        allowEarlyReturn: Bool,
        earlyReturnLeadSecs: Double
    ) -> [BreakTimingWarning] {
        let postponeExceeds = allowPostpone && postponeWindowSecs > restDurationSecs
        let leadExceeds = allowEarlyReturn && earlyReturnLeadSecs > restDurationSecs

        var warnings: [BreakTimingWarning] = []
        if postponeExceeds { warnings.append(.postponeWindowExceedsRest) }
        if leadExceeds { warnings.append(.earlyReturnLeadExceedsRest) }

        // Overlap is only reported as its own case when neither window individually
        // exceeds the break; otherwise the "exceeds" warning already explains the
        // collision and a second message would be redundant.
        let windowsOverlap = allowPostpone && allowEarlyReturn
            && !postponeExceeds && !leadExceeds
            && postponeWindowSecs + earlyReturnLeadSecs > restDurationSecs
        if windowsOverlap { warnings.append(.windowsOverlap) }

        return warnings
    }
}
