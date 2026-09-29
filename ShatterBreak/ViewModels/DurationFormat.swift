import Foundation

/// Parsing, formatting and snapping for durations in seconds.
enum DurationFormat {
    /// Seconds from "1h 5m", "01:30", "90" (minutes) or "1:02:03"; `nil` if invalid.
    static func parse(_ rawInput: String) -> Double? {
        let input = rawInput
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard input.isEmpty == false else { return nil }

        if input.contains("h") || input.contains("m") || input.contains("s") {
            return parsedComponentSeconds(from: input)
        }

        return parsedColonSeparatedSeconds(from: input)
    }

    /// Rejected or non-positive input leaves `current` unchanged.
    static func applying(input: String, to current: Double, min: Double, max: Double) -> Double {
        guard let parsed = parse(input), parsed > 0 else { return current }
        return Swift.max(min, Swift.min(parsed, max))
    }

    static func snap(rawSeconds: Double, min: Double, max: Double) -> Double {
        let step = scaleStep(for: rawSeconds)
        let snapped = (rawSeconds / step).rounded() * step
        return Swift.max(min, Swift.min(snapped, max))
    }

    /// Stepping down picks the scale from just below the value, so leaving a boundary (60s,
    /// 600s) takes the finer step.
    static func step(from seconds: Double, descending: Bool) -> Double {
        scaleStep(for: descending ? seconds - 1 : seconds)
    }

    private static func scaleStep(for seconds: Double) -> Double {
        switch seconds {
        case ..<60: 5
        case 60..<600: 60
        default: 300
        }
    }

    // MARK: - Display formatting

    /// "1h 5m" above an hour, otherwise "MM:SS".
    static func friendly(_ seconds: Double) -> String {
        let wholeSeconds = Int(seconds)
        guard wholeSeconds >= 3600 else { return clock(seconds) }

        // "2h 0m", not "2h 0m 0s".
        let allowedUnits: Set<Duration.UnitsFormatStyle.Unit> = wholeSeconds % 60 == 0
            ? [.hours, .minutes]
            : [.hours, .minutes, .seconds]

        return Duration.seconds(wholeSeconds).formatted(
            .units(allowed: allowedUnits, width: .narrow, zeroValueUnits: .show(length: 1))
        )
    }

    /// Minutes are not capped at 59.
    static func clock(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(zeroPadded(totalMinutes)):\(zeroPadded(remainingSeconds))"
    }

    // MARK: - Parsing helpers

    /// A closed range here caps as well as pads, truncating past 99.
    private static func zeroPadded(_ value: Int) -> String {
        value.formatted(.number.precision(.integerLength(2...)))
    }

    private static func parsedComponentSeconds(from input: String) -> Double? {
        let matches = input.matches(of: /(\d+(?:\.\d+)?)([hms])\s*/)
        guard matches.isEmpty == false else { return nil }

        var consumedLength = 0
        var totalSeconds = 0.0

        for match in matches {
            consumedLength += match.output.0.count

            guard let value = Double(String(match.output.1)) else {
                return nil
            }

            switch String(match.output.2) {
            case "h":
                totalSeconds += value * 3600
            case "m":
                totalSeconds += value * 60
            case "s":
                totalSeconds += value
            default:
                return nil
            }
        }

        guard consumedLength == input.count else { return nil }
        return totalSeconds
    }

    private static func parsedColonSeparatedSeconds(from input: String) -> Double? {
        let hasColon = input.contains(":")

        if hasColon == false {
            guard let value = Double(input) else { return nil }
            return value * 60
        }

        let rawComponents = input.split(separator: ":", omittingEmptySubsequences: false)
        guard rawComponents.count == 2 || rawComponents.count == 3 else { return nil }

        let components = rawComponents.compactMap(strictClockComponent)
        guard components.count == rawComponents.count else { return nil }

        return switch components.count {
        case 2:
            Double(components[0] * 60 + components[1])
        case 3:
            Double(components[0] * 3600 + components[1] * 60 + components[2])
        default:
            nil
        }
    }

    private static func strictClockComponent(_ component: Substring) -> Int? {
        guard component.isEmpty == false else { return nil }
        guard component.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(component)
    }
}
