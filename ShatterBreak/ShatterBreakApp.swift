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
                Text(timerState.formattedTimeRemaining)
                    .font(.system(.body, design: .monospaced))
            }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environment(\.permissions, permissions)
                .task { permissions.requestIfFirstLaunch() }
        }
        .windowResizability(.contentSize)
    }
}

// Use the shared manager so missing injection does not silently create fresh state.
private struct PermissionsKey: EnvironmentKey {
    static var defaultValue: ScreenCapturePermissionManager {
        MainActor.assumeIsolated { ScreenCapturePermissionManager.shared }
    }
}

extension EnvironmentValues {
    var permissions: ScreenCapturePermissionManager {
        get { self[PermissionsKey.self] }
        set { self[PermissionsKey.self] = newValue }
    }
}
