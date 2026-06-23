import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    // State is initialized on MainActor since App is @MainActor
    @State private var timerState = TimerState()
    @State private var permissions = ScreenCapturePermissionManager.shared
    @AppStorage(PreferenceKeys.showTimerInMenuBar)
    private var showTimerInMenuBar = PreferenceDefaults.showTimerInMenuBar

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
                .moveToActiveSpace()
        }
        .windowResizability(.contentSize)

        Window(.about, id: "about") {
            AboutView()
                .moveToActiveSpace()
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
