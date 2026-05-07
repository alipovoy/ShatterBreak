import SwiftUI

@MainActor
@Observable
final class DurationSliderViewModel {
    var manualInput: String = ""
    var isEditing = false

    func syncManualInput(with seconds: Double, isInputFocused: Bool) {
        manualInput = isInputFocused ? formatTimeMMSS(seconds: seconds) : formatTime(seconds: seconds)
    }

    func updateValueFromInput(currentValue: inout Double, min: Double, max: Double) {
        let cleanInput = manualInput
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let totalSeconds = parsedSeconds(from: cleanInput), totalSeconds > 0 {
            currentValue = Swift.max(min, Swift.min(totalSeconds, max))
        }

        manualInput = formatTime(seconds: currentValue)
    }

    func sliderBinding(for valueBinding: Binding<Double>, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: {
                PiecewiseTimer.position(from: valueBinding.wrappedValue)
            },
            set: { newValue in
                let rawSeconds = PiecewiseTimer.seconds(from: newValue)

                let step: Double = switch rawSeconds {
                case ..<60: 5
                case 60..<600: 60
                default: 300
                }

                let snappedSeconds = round(rawSeconds / step) * step
                valueBinding.wrappedValue = Swift.max(min, Swift.min(snappedSeconds, max))
            }
        )
    }

    // MARK: - Formatting

    func formatTime(seconds: Double) -> String {
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

    private func formatTimeMMSS(seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return "\(zeroPadded(totalMinutes)):\(zeroPadded(remainingSeconds))"
    }

    private func zeroPadded(_ value: Int) -> String {
        value.formatted(.number.precision(.integerLength(2...2)))
    }

    private func parsedSeconds(from input: String) -> Double? {
        guard input.isEmpty == false else { return nil }

        if input.contains("h") || input.contains("m") || input.contains("s") {
            return parsedComponentSeconds(from: input)
        }

        return parsedColonSeparatedSeconds(from: input)
    }

    private func parsedComponentSeconds(from input: String) -> Double? {
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

    private func parsedColonSeparatedSeconds(from input: String) -> Double? {
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

    private func strictClockComponent(_ component: Substring) -> Int? {
        guard component.isEmpty == false else { return nil }
        guard component.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(component)
    }
}
