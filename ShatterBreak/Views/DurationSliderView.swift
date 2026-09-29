import SwiftUI

struct DurationSliderView: View {
    let title: LocalizedStringResource
    let systemImage: String?
    @Binding var value: Double
    let min: Double
    let max: Double
    var disabled: Bool = false
    /// The default fits hour-scale durations ("1h 5m").
    var inputWidth: CGFloat = 85

    @State private var isEditing = false

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
                // Reclaims the label gutter a grouped Form reserves.
                .labelsHidden()
                .disabled(disabled)

                DurationTextField(title: title, value: $value, min: min, max: max)
                    .frame(width: inputWidth, alignment: .trailing)
                    .disabled(disabled)
                    .foregroundStyle(isEditing ? Color.accentColor : .primary)
            }
        }
        .padding(10)
        // One full-width cell, not a Form's label/control pair.
        .frame(maxWidth: .infinity, alignment: .leading)
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
