import SwiftUI

struct MenuView: View {
    @ObservedObject var state: TimerState

    // Tracks which text field is currently active for input validation
    enum FocusedField {
        case work, rest
    }
    @FocusState private var focusedField: FocusedField?

    var body: some View {
        VStack(spacing: 16) {
            // Header / Timer Display
            VStack {
                if state.isRunning || state.isPaused {
                    Text(timeString(from: state.timeRemaining))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(state.isResting ? .green : .primary)
                } else {
                    Text("Ready")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 60)

            // Main Controls for Start/Pause/Stop
            HStack(spacing: 12) {
                if state.isRunning || state.isPaused {
                    Button(action: {
                        state.isPaused ? state.resume() : state.pause()
                    }) {
                        Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button(action: { state.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button(action: { state.start() }) {
                        Label("Start Focus", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            // Configuration Sliders for durations
            VStack(alignment: .leading, spacing: 12) {
                // Work Timer Row
                Text("Work Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(.secondary)

                    Slider(value: logBinding(for: $state.workDurationSecs, min: 5, max: 7200), in: 0...1)

                    TextField("Secs", value: $state.workDurationSecs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .work)
                        .onSubmit { validateInputs() }

                    Text("sec")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(state.isRunning)

                // Rest Timer Row
                Text("Rest Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 4)

                HStack {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundColor(.secondary)

                    Slider(value: logBinding(for: $state.restDurationSecs, min: 5, max: 3600), in: 0...1)

                    TextField("Secs", value: $state.restDurationSecs, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 55)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .rest)
                        .onSubmit { validateInputs() }

                    Text("sec")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(state.isRunning)
            }

            Divider()

            // Footer with Quit button
            HStack {
                Spacer()
                Button("Quit", action: {
                    NSApp.terminate(nil) // macOS
                })
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .onChange(of: focusedField) { oldFocus, newFocus in
            if newFocus == nil {
                validateInputs()
            }
        }
    }

    // MARK: - Helpers

    private func validateInputs() {
        // Ensure work duration is within a valid range
        if state.workDurationSecs < 5 { state.workDurationSecs = 5 }
        if state.workDurationSecs > 7200 { state.workDurationSecs = 7200 }

        // Ensure rest duration is within a valid range
        if state.restDurationSecs < 5 { state.restDurationSecs = 5 }
        if state.restDurationSecs > 3600 { state.restDurationSecs = 3600 }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // Creates a logarithmic binding for the slider to provide better control over large ranges
    private func logBinding(for value: Binding<Double>, min: Double, max: Double) -> Binding<Double> {
        Binding(
            get: {
                let clampedValue = Swift.max(min, Swift.min(value.wrappedValue, max))
                return log(clampedValue / min) / log(max / min)
            },
            set: { newValue in
                let newSeconds = min * pow((max / min), newValue)
                value.wrappedValue = round(newSeconds)
            }
        )
    }
}
