import SwiftUI

/// A duration typed by hand: "25m" at rest, the editable "25:00" while focused, applied on
/// Return or on losing focus and reverted on Escape.
struct DurationTextField: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let min: Double
    let max: Double

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        // The label is the accessibility name only; a Form would otherwise show it beside
        // the field.
        TextField(text: $text, prompt: Text(verbatim: "00:00")) {
            Text(title)
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .font(.body.monospacedDigit())
        .multilineTextAlignment(.trailing)
        .focused($isFocused)
        .onSubmit {
            commit()
            isFocused = false
        }
        .onExitCommand {
            text = DurationFormat.friendly(value)
            isFocused = false
        }
        .onAppear { text = displayText(for: value) }
        .onChange(of: value) { _, newValue in
            text = displayText(for: newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                text = DurationFormat.clock(value)
            } else {
                commit()
            }
        }
    }

    private func displayText(for seconds: Double) -> String {
        isFocused ? DurationFormat.clock(seconds) : DurationFormat.friendly(seconds)
    }

    private func commit() {
        value = DurationFormat.applying(input: text, to: value, min: min, max: max)
        text = DurationFormat.friendly(value)
    }
}
