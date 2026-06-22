import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    // State is initialized on MainActor since App is @MainActor
    @State private var timerState = TimerState()
    @State private var permissions = ScreenCapturePermissionManager.shared
    @AppStorage(PreferenceKeys.showTimerInMenuBar) private var showTimerInMenuBar: Bool = false

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: timerState)
                .task { permissions.requestIfFirstLaunch() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "app.badge.clock")

                if showTimerInMenuBar && timerState.shouldShowTimeInMenuBar {
                    CountdownTextView(state: timerState)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window(.preferences, id: "preferences") {
            PreferencesView()
                .environment(\.permissions, permissions)
                .task { permissions.requestIfFirstLaunch() }
        }
        .windowResizability(.contentSize)

        // Title is rendered centered via a principal toolbar item in AboutView,
        // so the window's own (left-aligned) title is left empty to avoid duplication.
        Window("", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

extension EnvironmentValues {
    // Use the shared manager so missing injection does not silently create fresh state.
    @Entry var permissions: ScreenCapturePermissionManager = MainActor.assumeIsolated {
        ScreenCapturePermissionManager.shared
    }
}
