import SwiftUI

struct DurationFieldView: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let min: Double
    let max: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                DurationTextField(title: title, value: $value, min: min, max: max)
                    .frame(width: 80)

                Stepper {
                    Text(title)
                } onIncrement: {
                    adjust(by: DurationFormat.step(from: value, descending: false))
                } onDecrement: {
                    adjust(by: -DurationFormat.step(from: value, descending: true))
                }
                .labelsHidden()
            }
        } label: {
            Text(title)
        }
    }

    private func adjust(by delta: Double) {
        value = Swift.max(min, Swift.min(value + delta, max))
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
