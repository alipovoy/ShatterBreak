import SwiftUI

struct MenuView: View {
    @Bindable var state: TimerState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.permissions) private var permissions

    var onQuit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        VStack(spacing: 16) {
            timerDisplay

            HStack(spacing: 12) {
                if state.isRunning || state.isPaused {
                    Button {
                        state.isPaused ? state.resume() : state.pause()
                    } label: {
                        Label(
                            state.isPaused ? "Resume" : (state.isResting ? "Skip Rest" : "Pause"),
                            systemImage: state.isPaused
                                ? "play.fill" : (state.isResting ? "forward.fill" : "pause.fill")
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button {
                        state.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        state.start()
                    } label: {
                        Label("Start Focus", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

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

            footer
        }
        .padding()
        .frame(width: 320)
    }

    @ViewBuilder
    private var timerDisplay: some View {
        Group {
            if state.isRunning || state.isPaused {
                Text(formattedTime(state.timeRemaining))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(state.isResting ? .green : .primary)
            } else {
                Text("Ready")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 60)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        // delegate to TimerState helper so formatting remains consistent
        return TimerState.format(timeInterval: interval)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Preferences", systemImage: "gearshape") {
                openWindow(id: "preferences")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button("Quit") {
                onQuit()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
    }
}

#Preview("MenuView") { @MainActor in
    MenuView(state: TimerState(), onQuit: { })
}
