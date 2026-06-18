import SwiftUI

struct DurationSliderView: View {
    let title: LocalizedStringResource
    let systemImage: String
    @Binding var value: Double
    let min: Double
    let max: Double
    let disabled: Bool

    @State private var viewModel = DurationSliderViewModel()
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
                    value: viewModel.sliderBinding(for: $value, min: min, max: max),
                    in: 0...PiecewiseTimer.position(from: max),
                    onEditingChanged: { editing in
                        viewModel.isEditing = editing
                    }
                )
                .disabled(disabled)

                TextField("00:00", text: $viewModel.manualInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .frame(width: 85, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .focused($isInputFocused)
                    .disabled(disabled)
                    .foregroundStyle(viewModel.isEditing ? Color.accentColor : .primary)
                    .onChange(of: isInputFocused) { _, isFocused in
                        if isFocused {
                            viewModel.syncManualInput(with: value, isInputFocused: true)
                        } else {
                            viewModel.updateValueFromInput(currentValue: &value, min: min, max: max)
                        }
                    }
                    .onSubmit {
                        viewModel.updateValueFromInput(currentValue: &value, min: min, max: max)
                        isInputFocused = false
                    }
                    .onExitCommand {
                        viewModel.syncManualInput(with: value, isInputFocused: false)
                        isInputFocused = false
                    }
            }
        }
        .padding(10)
        .onAppear {
            viewModel.syncManualInput(with: value, isInputFocused: isInputFocused)
        }
        .onChange(of: value) { _, newValue in
            viewModel.syncManualInput(with: newValue, isInputFocused: isInputFocused)
        }
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
