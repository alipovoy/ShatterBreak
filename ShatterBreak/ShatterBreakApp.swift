import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var permissions = ScreenCapturePermissionManager.shared

    // No scene requests screen-capture permission on appearance: opening the menu or
    // Preferences says nothing about whether a capture is imminent, and asking there
    // prompted users who had chosen Fogged or Dimmed. Every request now follows an action
    // meaning "I want Shatter to work" — see `ScreenCaptureConsentView`.
    //
    // The status item is not a scene: `MenuBarExtra` discards font and layout modifiers on
    // its label, so the countdown could not hold a width. `MenuBarController` owns it.
    var body: some Scene {
        // A plain Window rather than a Settings scene: TabView renders here with the
        // capsule-toolbar tabs, and Xcode previews match the app exactly. The scene's
        // usual perk (a standard ⌘, shortcut) has no menu bar to live in anyway.
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

/// An accessory app with no `MenuBarExtra` shows nothing at launch, so there is no view
/// lifecycle to hang the status item or the auto-start on.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let timerState = TimerState()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(state: timerState, defaults: timerState.defaults)
        timerState.autoStartIfEnabled()
    }
}

extension EnvironmentValues {
    // Use the shared manager so missing injection does not silently create fresh state.
    @Entry var permissions: ScreenCapturePermissionManager = .environmentDefault
}

// Stored, not written inline as the `@Entry` default: that default is re-evaluated on
// every access, so Xcode 27 flags a class-typed one whatever the expression returns —
// it cannot see that this closure hands back the one shared instance. A `let` also
// settles the main-actor hop once instead of on every read.
extension ScreenCapturePermissionManager {
    nonisolated fileprivate static let environmentDefault = MainActor.assumeIsolated { shared }
}
