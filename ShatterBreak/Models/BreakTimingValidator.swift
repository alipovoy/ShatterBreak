import Foundation

/// A contradiction between the break-timing settings and the break length, warned about
/// rather than silently clamped.
enum BreakTimingWarning: Hashable {
    /// The Postpone window is longer than the break, so Postpone never auto-hides.
    case postponeWindowExceedsRest
    /// The early-return lead is longer than the break, so "I'm back" shows throughout.
    case earlyReturnLeadExceedsRest
    /// The Postpone and "I'm back" windows overlap, leaving no button-free rest gap.
    case windowsOverlap

    var message: LocalizedStringResource {
        switch self {
        case .postponeWindowExceedsRest: .postponeWindowExceedsRestWarning
        case .earlyReturnLeadExceedsRest: .earlyReturnLeadExceedsRestWarning
        case .windowsOverlap: .windowsOverlapWarning
        }
    }
}

/// Strictly greater than rest: a window equal to the break, or windows that exactly meet,
/// are fine.
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

        // Only when neither window alone exceeds the break, which already explains it.
        let windowsOverlap = allowPostpone && allowEarlyReturn
            && !postponeExceeds && !leadExceeds
            && postponeWindowSecs + earlyReturnLeadSecs > restDurationSecs
        if windowsOverlap { warnings.append(.windowsOverlap) }

        return warnings
    }
}
