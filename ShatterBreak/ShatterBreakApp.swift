import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    // State is initialized on MainActor since App is @MainActor
    @State private var timerState = TimerState()
    @State private var permissions = ScreenCapturePermissionManager()
    @AppStorage("showTimerInMenuBar") private var showTimerInMenuBar: Bool = false

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: timerState)
                .environment(\.permissions, permissions)
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

// Environment key with optional to avoid default initialization
private struct PermissionsKey: EnvironmentKey {
    static let defaultValue: ScreenCapturePermissionManager? = nil
}

extension EnvironmentValues {
    var permissions: ScreenCapturePermissionManager {
        get { self[PermissionsKey.self] ?? MainActor.assumeIsolated { ScreenCapturePermissionManager() } }
        set { self[PermissionsKey.self] = newValue }
    }
}

