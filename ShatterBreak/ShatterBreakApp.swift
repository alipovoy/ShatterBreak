import SwiftUI

@main
struct ShatterBreakApp: App {
    @StateObject private var timerState = TimerState()
    @StateObject private var permissionManager = ScreenCapturePermissionManager()

    var body: some Scene {
        MenuBarExtra("ShatterBreak", systemImage: "app.badge.clock") {
            MenuView(state: timerState)
                .environmentObject(permissionManager)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(permissionManager)
        }
        .windowResizability(.contentSize)
    }
}
