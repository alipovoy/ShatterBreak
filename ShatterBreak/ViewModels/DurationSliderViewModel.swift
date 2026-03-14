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
            .replacing("h", with: ":")
            .replacing("m", with: ":")
            .replacing("s", with: ":")
            .replacing(" ", with: "")

        let rawComponents = cleanInput.split(separator: ":")
        var totalSeconds: Double = 0

        if !rawComponents.isEmpty {
            if rawComponents.count == 1 {
                let val = Double(rawComponents[0]) ?? 0
                if cleanInput.contains(":") {
                    totalSeconds = val
                } else {
                    totalSeconds = val * 60
                }
            } else {
                let reversed = Array(rawComponents.reversed())
                let secs = Double(reversed[0]) ?? 0
                totalSeconds += secs

                if reversed.count > 1 {
                    let mins = Double(reversed[1]) ?? 0
                    totalSeconds += mins * 60
                }

                if reversed.count > 2 {
                    let hrs = Double(reversed[2]) ?? 0
                    totalSeconds += hrs * 3600
                }
            }
        }

        if totalSeconds > 0 {
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
}
