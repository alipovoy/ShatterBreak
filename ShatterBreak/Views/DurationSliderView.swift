import SwiftUI

struct DurationSliderView: View {
    let title: LocalizedStringResource
    let systemImage: String
    @Binding var value: Double
    let min: Double
    let max: Double
    let disabled: Bool

    @State private var manualInput = ""
    @State private var isEditing = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline)
                .bold()

            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                Slider(
                    value: sliderBinding,
                    in: 0...PiecewiseTimer.position(from: max),
                    onEditingChanged: { editing in
                        isEditing = editing
                    }
                )
                .disabled(disabled)

                TextField("00:00", text: $manualInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .frame(width: 85, alignment: .trailing)
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
        min: 5,
        max: 7200,
        disabled: false
    )
}
