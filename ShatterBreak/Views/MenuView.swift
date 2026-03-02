import SwiftUI

struct MenuView: View {
    @ObservedObject var state: TimerState

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
            VStack(alignment: .leading, spacing: 16) {
                DurationSliderView(
                    title: "Work Duration",
                    systemImage: "briefcase.fill",
                    value: $state.workDurationSecs,
                    min: 5,
                    max: 7200,
                    disabled: state.isRunning
                )

                DurationSliderView(
                    title: "Rest Duration",
                    systemImage: "cup.and.saucer.fill",
                    value: $state.restDurationSecs,
                    min: 5,
                    max: 3600,
                    disabled: state.isRunning
                )
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
    }

    // MARK: - Helpers

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        let seconds = max(0, Int(interval) % 60)
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
