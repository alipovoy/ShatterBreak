import SwiftUI

@main
@MainActor
struct ShatterBreakApp: App {
    // State is initialized on MainActor since App is @MainActor
    @State private var timerState = TimerState()
    @State private var permissions = ScreenCapturePermissionManager.shared
    @AppStorage(PreferenceKeys.menuBarTimerStyle)
    private var menuBarTimerStyle = PreferenceDefaults.menuBarTimerStyle

    init() {
        MenuBarTimerStyle.migrateLegacyShowTimerPreference(in: UserDefaults.standard)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: timerState)
                .task { permissions.requestIfFirstLaunch() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "app.badge.clock")

                if timerState.shouldShowTimeInMenuBar,
                   let displayStyle = menuBarTimerStyle.countdownDisplayStyle {
                    CountdownTextView(state: timerState, displayStyle: displayStyle)
                        .font(.system(.body, design: .monospaced))
                }
            }
            // The label is always rendered, so this fires once at launch — unlike the
            // menu content, which is built lazily when the user opens the menu.
            .task { timerState.autoStartIfEnabled() }
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
