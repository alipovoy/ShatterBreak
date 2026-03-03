import Foundation
import Combine
import AppKit
import CoreGraphics

/// Centralises screen-capture permission state for the entire app.
///
/// Responsibilities:
/// - Performs the one-time first-launch permission request.
/// - Publishes live `Status` so UI can react declaratively.
/// - Refreshes automatically when the app regains focus (covers the case
///   where the user toggled the setting in System Settings and returned).
@MainActor
final class ScreenCapturePermissionManager: ObservableObject {

    // MARK: - Types

    enum Status {
        /// `CGPreflightScreenCaptureAccess()` returned `true`.
        case granted
        /// Access was requested at least once but not granted.
        case denied
        /// App has never requested access (pre-first-launch dialog).
        case notDetermined
    }

    // MARK: - Published

    @Published private(set) var status: Status = .notDetermined

    // MARK: - Private

    private static let launchKey = "com.shatterbreak.hasLaunchedBefore"
    private var observation: AnyCancellable?

    // MARK: - Init

    init() {
        requestPermissionIfFirstLaunch()
        refresh()
        observeAppActive()
    }

    // MARK: - Public API

    /// Re-reads the system permission state synchronously.
    /// Call on `onAppear` for an immediate refresh on any view that shows permission-sensitive UI.
    func refresh() {
        if CGPreflightScreenCaptureAccess() {
            status = .granted
        } else {
            status = hasLaunchedBefore ? .denied : .notDetermined
        }
    }

    /// Opens the Screen Recording pane directly in System Settings.
    func openSystemSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    // MARK: - Private helpers

    private var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.launchKey)
    }

    /// Shows the one-time system dialog on the very first launch.
    /// On subsequent launches the live system state is the source of truth.
    private func requestPermissionIfFirstLaunch() {
        guard !hasLaunchedBefore else { return }
        UserDefaults.standard.set(true, forKey: Self.launchKey)
        CGRequestScreenCaptureAccess()
    }

    private func observeAppActive() {
        observation = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }
}
