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
                    disabled: !state.canEditDurations
                )

                DurationSliderView(
                    title: "Rest Duration",
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
                Button("Preferences", systemImage: "gearshape", action: openPreferences)
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button("Quit", action: onQuit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
        .background(MenuWindowVisibilityObserver(isVisible: $isWindowVisible))
    }

    private func openPreferences() {
        openWindow(id: "preferences")
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

private struct MenuWindowVisibilityObserver: NSViewRepresentable {
    @Binding var isVisible: Bool

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    @MainActor
    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { window in
            context.coordinator.observe(window: window)
        }
        return view
    }

    @MainActor
    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.isVisible = $isVisible
        context.coordinator.updateVisibility()
    }

    @MainActor
    final class Coordinator: NSObject {
        var isVisible: Binding<Bool>
        private weak var window: NSWindow?

        init(isVisible: Binding<Bool>) {
            self.isVisible = isVisible
        }

        func observe(window: NSWindow?) {
            guard self.window !== window else {
                updateVisibility()
                return
            }

            removeObservers()
            self.window = window

            guard let window else {
                isVisible.wrappedValue = false
                return
            }

            let center = NotificationCenter.default
            let names: [NSNotification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification
            ]

            names.forEach { name in
                center.addObserver(
                    self,
                    selector: #selector(handleWindowNotification(_:)),
                    name: name,
                    object: window
                )
            }

            updateVisibility()
        }

        @objc private func handleWindowNotification(_ notification: Notification) {
            updateVisibility()
        }

        func updateVisibility() {
            guard let window else {
                if isVisible.wrappedValue {
                    isVisible.wrappedValue = false
                }
                return
            }

            let nextValue = window.isVisible && window.occlusionState.contains(.visible)
            if isVisible.wrappedValue != nextValue {
                isVisible.wrappedValue = nextValue
            }
        }

        private func removeObservers() {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class WindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

#Preview("MenuView") { @MainActor in
    MenuView(state: TimerState(), onQuit: { })
}
