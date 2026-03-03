import SwiftUI
import AppKit
import Combine
import ScreenCaptureKit // Required for modern screen capture

@main
struct ShatterBreakApp: App {
    @StateObject private var timerState = TimerState()


    init() {
        // Pre-flight check on launch so the user gets prompted immediately
        // while they still have normal desktop access.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    var body: some Scene {
        MenuBarExtra("ShatterBreak", systemImage: "app.badge.clock") {
            MenuView(state: timerState)
        }
        .menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
        }
        .windowResizability(.contentSize)
    }
}
