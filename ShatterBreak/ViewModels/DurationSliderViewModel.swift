import SwiftUI

struct SliderAnchor: Sendable {
    let stop: Double
    let value: Double
}

struct PiecewiseTimer: Sendable {
    static let anchors: [SliderAnchor] = [
        SliderAnchor(stop: 0.0,  value: 5),
        SliderAnchor(stop: 0.1,  value: 30),
        SliderAnchor(stop: 0.2,  value: 60),
        SliderAnchor(stop: 0.3,  value: 300),
        SliderAnchor(stop: 0.4,  value: 600),
        SliderAnchor(stop: 0.5,  value: 900),
        SliderAnchor(stop: 0.6,  value: 1500),
        SliderAnchor(stop: 0.7,  value: 2700),
        SliderAnchor(stop: 0.8,  value: 3300),
        SliderAnchor(stop: 0.9,  value: 5400),
        SliderAnchor(stop: 1.0,  value: 7200)
    ]

    static func seconds(from t: Double) -> Double {
        guard anchors.count >= 2 else { return anchors.first?.value ?? 0 }
        
        for i in 0..<anchors.count - 1 {
            let start = anchors[i]
            let end = anchors[i+1]

            if t <= end.stop {
                let localT = (t - start.stop) / (end.stop - start.stop)
                return start.value + localT * (end.value - start.value)
            }
        }
        return anchors.last?.value ?? 0
    }

    static func position(from seconds: Double) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        
        if seconds <= first.value { return first.stop }
        if seconds >= last.value { return last.stop }

        for i in 0..<anchors.count - 1 {
            let start = anchors[i]
            let end = anchors[i+1]

            if seconds <= end.value {
                let localT = (seconds - start.value) / (end.value - start.value)
                return start.stop + localT * (end.stop - start.stop)
            }
        }
        return last.stop
    }
}

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
