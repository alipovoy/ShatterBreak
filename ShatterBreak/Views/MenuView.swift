import AppKit
import SwiftUI

struct MenuView: View {
    @Bindable var state: TimerState
    @Environment(\.openWindow) private var openWindow
    @State private var isWindowVisible = false

    var onQuit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        VStack(spacing: 16) {
            TimerDisplayView(state: state, isActive: isWindowVisible)

            HStack(spacing: 12) {
                if state.isRunning || state.isPaused {
                    Button {
                        state.isPaused ? state.resume() : state.pause()
                    } label: {
                        Label(
                            state.isPaused ? .resume : (state.isResting ? .skipRest : .pause),
                            systemImage: state.isPaused
                                ? "play.fill" : (state.isResting ? "forward.fill" : "pause.fill")
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button {
                        state.stop()
                    } label: {
                        Label(.stop, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        state.start()
                    } label: {
                        Label(.startFocus, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                DurationSliderView(
                    title: .workDuration,
                    systemImage: "briefcase.fill",
                    value: $state.workDurationSecs,
                    min: 5,
                    max: 7200,
                    disabled: !state.canEditDurations
                )

                DurationSliderView(
                    title: .restDuration,
                    systemImage: "cup.and.saucer.fill",
                    value: $state.restDurationSecs,
                    min: 5,
                    max: 3600,
                    disabled: !state.canEditDurations
                )
            }

            Divider()

            // Keep these local actions inline; a separate footer view would add only pass-through inputs.
            HStack {
                Button(.preferences, systemImage: "gearshape", action: openPreferences)
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button(.quit, action: onQuit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .overlay(alignment: .topTrailing) {
            Button(.about, systemImage: "info.circle", action: openAbout)
                .labelStyle(.iconOnly)
                .buttonStyle(IconButtonStyle())
                .padding(.all)
        }
        .background(MenuWindowVisibilityObserver(isVisible: $isWindowVisible))
    }

    private func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "preferences")
    }

    private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }
}

#Preview("MenuView") { @MainActor in
    MenuView(state: TimerState(), onQuit: { })
}
