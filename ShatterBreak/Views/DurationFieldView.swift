import SwiftUI

/// A single-line duration row for Settings: title on the leading edge, an editable
/// MM:SS field plus a stepper trailing. The menu keeps ``DurationSliderView`` for
/// quick coarse adjustment; this row trades the slider for precision and height.
struct DurationFieldView: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let min: Double
    let max: Double

    @State private var manualInput = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                // The label is the field's accessibility name only; a Form would
                // otherwise promote it to a visible label beside the field, so it
                // is hidden and the placeholder moved to `prompt`.
                TextField(text: $manualInput, prompt: Text(verbatim: "00:00")) {
                    Text(title)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($isInputFocused)
                .onSubmit {
                    commitManualInput()
                    isInputFocused = false
                }
                .onExitCommand {
                    manualInput = DurationFormat.friendly(value)
                    isInputFocused = false
                }

                Stepper {
                    Text(title)
                } onIncrement: {
                    adjust(by: incrementStep)
                } onDecrement: {
                    adjust(by: -decrementStep)
                }
                .labelsHidden()
            }
        } label: {
            Text(title)
        }
        .onAppear { manualInput = displayText(for: value) }
        .onChange(of: value) { _, newValue in
            manualInput = displayText(for: newValue)
        }
        .onChange(of: isInputFocused) { _, isFocused in
            if isFocused {
                manualInput = DurationFormat.clock(value)
            } else {
                commitManualInput()
            }
        }
    }

    /// Clock format while editing (parseable as typed back), friendly otherwise.
    private func displayText(for seconds: Double) -> String {
        isInputFocused ? DurationFormat.clock(seconds) : DurationFormat.friendly(seconds)
    }

    private func commitManualInput() {
        value = DurationFormat.applying(input: manualInput, to: value, min: min, max: max)
        manualInput = DurationFormat.friendly(value)
    }

    private func adjust(by delta: Double) {
        value = Swift.max(min, Swift.min(value + delta, max))
    }

    // Step sizes mirror the slider's snap scale (5s / 1m / 5m). The decrement step
    // is chosen from just below the current value so stepping down from a scale
    // boundary (60s, 600s) descends through the finer scale instead of jumping.
    private var incrementStep: Double {
        switch value {
        case ..<60: 5
        case 60..<600: 60
        default: 300
        }
    }

    private var decrementStep: Double {
        switch value {
        case ...60: 5
        case 60...600: 60
        default: 300
        }
    }
}

#Preview("DurationFieldView") {
    @Previewable @State var value: Double = 180
    Form {
        DurationFieldView(
            title: "Rest Duration",
            value: $value,
            min: DurationBounds.minimumSecs,
            max: DurationBounds.restMaximumSecs
        )
    }
    .formStyle(.grouped)
}
