import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    // State is initialized on MainActor since App is @MainActor
    @State private var timerState = TimerState()
    @State private var permissions = ScreenCapturePermissionManager()

    var body: some Scene {
        MenuBarExtra("ShatterBreak", systemImage: "app.badge.clock") {
            MenuView(state: timerState)
                .environment(\.permissions, permissions)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environment(\.permissions, permissions)
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

