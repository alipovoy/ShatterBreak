import SwiftUI

struct DurationSliderView: View {
    let title: LocalizedStringResource
    /// Leading glyph for the row; pass `nil` to omit it (e.g. in Preferences, where the
    /// titles already read as a settings list and an icon would only add clutter).
    let systemImage: String?
    @Binding var value: Double
    let min: Double
    let max: Double
    var disabled: Bool = false
    /// Width of the trailing MM:SS field. The default fits the menu's hour-scale
    /// durations ("1h 5m"); short break windows can pass a narrower value.
    var inputWidth: CGFloat = 85

    @State private var manualInput = ""
    @State private var isEditing = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline)
                .bold()

            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: sliderBinding,
                    in: 0...PiecewiseTimer.position(from: max),
                    onEditingChanged: { editing in
                        isEditing = editing
                    }
                )
                // A grouped Form reserves a leading label gutter for each control; the
                // slider has no label, so hide it to reclaim that space and span the row.
                .labelsHidden()
                .disabled(disabled)

                // The label is the field's accessibility name only; a Form would
                // otherwise promote it to a visible "00:00" label beside the field,
                // so it is hidden and the placeholder moved to `prompt`.
                TextField(text: $manualInput, prompt: Text(verbatim: "00:00")) {
                    Text(title)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .frame(width: inputWidth, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .focused($isInputFocused)
                    .disabled(disabled)
                    .foregroundStyle(isEditing ? Color.accentColor : .primary)
                    .onChange(of: isInputFocused) { _, isFocused in
                        if isFocused {
                            manualInput = DurationFormat.clock(value)
                        } else {
                            commitManualInput()
                        }
                    }
                    .onSubmit {
                        commitManualInput()
                        isInputFocused = false
                    }
                    .onExitCommand {
                        manualInput = DurationFormat.friendly(value)
                        isInputFocused = false
                    }
            }
        }
        .padding(10)
        // Claim the full row width so a grouped Form lays the title and slider out as
        // one full-width cell instead of splitting them into a label/control column pair.
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            manualInput = isInputFocused ? DurationFormat.clock(value) : DurationFormat.friendly(value)
        }
        .onChange(of: value) { _, newValue in
            manualInput = isInputFocused ? DurationFormat.clock(newValue) : DurationFormat.friendly(newValue)
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { PiecewiseTimer.position(from: value) },
            set: { position in
                value = DurationFormat.snap(
                    rawSeconds: PiecewiseTimer.seconds(from: position),
                    min: min,
                    max: max
                )
            }
        )
    }

    private func commitManualInput() {
        value = DurationFormat.applying(input: manualInput, to: value, min: min, max: max)
        manualInput = DurationFormat.friendly(value)
    }
}

#Preview("DurationSliderView") {
    @Previewable @State var value: Double = 1500
    DurationSliderView(
        title: "Work Duration",
        systemImage: "timer",
        value: $value,
        min: DurationBounds.minimumSecs,
        max: DurationBounds.workMaximumSecs,
        disabled: false
    )
}
