import Foundation

/// Pure parsing, formatting, and snapping for duration values.
///
/// This logic used to live in a `DurationSliderViewModel`, but it holds no state — it
/// is just functions over `Double` seconds and `String` input. Keeping it as a plain
/// namespace lets `DurationSliderView` own its own `@State` and lets tests exercise the
/// fiddly parsing directly, without an `@Observable` wrapper.
enum DurationFormat {
    /// Parses user input ("1h 5m", "01:30", "90", "1:02:03") into total seconds, or
    /// `nil` if it is not a valid duration. Input is lowercased and trimmed first.
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

    /// Applies accepted input to `current`, clamped to `min...max`. Rejected or
    /// non-positive input leaves `current` unchanged.
    static func applying(input: String, to current: Double, min: Double, max: Double) -> Double {
        guard let parsed = parse(input), parsed > 0 else { return current }
        return Swift.max(min, Swift.min(parsed, max))
    }

    /// Snaps a raw slider duration to its step (5s / 60s / 300s) and clamps to `min...max`.
    static func snap(rawSeconds: Double, min: Double, max: Double) -> Double {
        let step: Double = switch rawSeconds {
        case ..<60: 5
        case 60..<600: 60
        default: 300
        }

        let snapped = (rawSeconds / step).rounded() * step
        return Swift.max(min, Swift.min(snapped, max))
    }

    // MARK: - Display formatting

    /// A reader-friendly duration: "1h 5m" above an hour, otherwise "MM:SS".
    static func friendly(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60

        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60

            var components = [
                "\(hours.formatted(.number))h",
                "\(mins.formatted(.number))m"
            ]

            if remainingSeconds > 0 {
                components.append("\(remainingSeconds.formatted(.number))s")
            }

            return components.joined(separator: " ")
        }

        return "\(zeroPadded(totalMinutes)):\(zeroPadded(remainingSeconds))"
    }

    /// An editable clock string ("MM:SS"); minutes are not capped at 59.
    static func clock(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(zeroPadded(totalMinutes)):\(zeroPadded(remainingSeconds))"
    }

    // MARK: - Parsing helpers

    private static func zeroPadded(_ value: Int) -> String {
        value.formatted(.number.precision(.integerLength(2...2)))
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
