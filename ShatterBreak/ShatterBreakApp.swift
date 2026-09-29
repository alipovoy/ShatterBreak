import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var permissions = ScreenCapturePermissionManager.shared

    // The status item is not a scene: `MenuBarExtra` drops font modifiers on its label, so
    // the countdown could not hold a width. `MenuBarController` owns it.
    var body: some Scene {
        // A plain Window rather than Settings: capsule-toolbar tabs, and previews that match.
        Window(.preferences, id: "preferences") {
            PreferencesView(state: delegate.timerState)
                .environment(\.permissions, permissions)
                .moveToActiveSpace()
        }
        .windowResizability(.contentSize)
        // The default presents whichever scene is declared first.
        .defaultLaunchBehavior(.suppressed)

        Window(.about, id: "about") {
            AboutView()
                .moveToActiveSpace()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// An accessory app with no scene on screen has no view lifecycle to start from.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let timerState = TimerState(
        overlays: OverlayManager()
    )
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(state: timerState)
        timerState.autoStartIfEnabled()
    }
}

extension EnvironmentValues {
    @Entry var permissions: ScreenCapturePermissionManager = .environmentDefault
}

// Stored: an inline `@Entry` default is re-evaluated on every access, and Xcode flags a
// class-typed one even when it returns a shared instance.
extension ScreenCapturePermissionManager {
    nonisolated fileprivate static let environmentDefault = MainActor.assumeIsolated { shared }
}
