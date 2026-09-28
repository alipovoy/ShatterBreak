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
                // A grouped Form reserves a leading label gutter for each control; the
                // slider has no label, so hide it to reclaim that space and span the row.
                .labelsHidden()
                .disabled(disabled)

                DurationTextField(title: title, value: $value, min: min, max: max)
                    .frame(width: inputWidth, alignment: .trailing)
                    .disabled(disabled)
                    .foregroundStyle(isEditing ? Color.accentColor : .primary)
            }
        }
        .padding(10)
        // Claim the full row width so a grouped Form lays the title and slider out as
        // one full-width cell instead of splitting them into a label/control column pair.
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
