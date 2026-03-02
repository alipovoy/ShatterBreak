import SwiftUI

struct DurationSliderView: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let min: Double
    let max: Double
    let disabled: Bool
    var focusedField: FocusState<MenuView.FocusedField?>.Binding
    let fieldEquals: MenuView.FocusedField
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)

                Slider(value: logBinding(for: $value, min: min, max: max), in: 0...1)
                    .disabled(disabled)

                TextField("MM:SS", value: $value, format: MinutesSecondsFormatStyle())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 65)
                    .multilineTextAlignment(.trailing)
                    .focused(focusedField, equals: fieldEquals)
                    .disabled(disabled)
                    .onSubmit { onSubmit() }
            }
        }
    }

    // Creates a logarithmic binding for the slider to provide better control over large ranges
    private func logBinding(for value: Binding<Double>, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: {
                let clampedValue = Swift.max(min, Swift.min(value.wrappedValue, max))
                return log(clampedValue / min) / log(max / min)
            },
            set: { newValue in

                // --- 1. MAGNET LOGIC ---
                // Define the exact timer values that should act as strong magnets: 5s, 30s, 1m, 5m, 10m, 30m, 60m, 90m, 120m
                let magnetTicks: [Double] = [5, 30, 60, 300, 600, 1500, 2700, 3300, 5400, 7200]
                let magnetStrength = 0.02 // Locks onto the tick if the slider is within 2% of it visually

                for tick in magnetTicks {
                    // Find where this tick lives visually on the 0...1 slider track
                    let tickPosition = log(Swift.max(min, tick) / min) / log(max / min)

                    // If the user's thumb is near this position, snap directly to the tick and return
                    if abs(newValue - tickPosition) < magnetStrength {
                        value.wrappedValue = Swift.max(min, Swift.min(tick, max))
                        return
                    }
                }

                // --- 2. REGULAR DYNAMIC STEP LOGIC (Fallback) ---
                let rawSeconds = min * pow((max / min), newValue)
                let step: Double
                switch rawSeconds {
                case ..<30:           // Under 30 seconds
                    step = 1          // 1-second steps
                case 30..<60:         // 0.5 to 1 minutes
                    step = 5          // 5-second steps
                case 60..<120:        // 1 to 2 minutes
                    step = 10         // 10-second steps
                case 120..<600:       // 2 to 10 minutes
                    step = 60         // 1-minute steps
                default:              // 10 minutes and over
                    step = 300        // 5-minute steps
                }

                // 3. Snap the value to the nearest step and update the state
                let snappedSeconds = round(rawSeconds / step) * step

                // Re-clamp just in case the snapping pushed us slightly over max or under min
                value.wrappedValue = Swift.max(min, Swift.min(snappedSeconds, max))
            }
        )
    }
}
