import Foundation

/// Application metadata read from the bundle's Info.plist.
///
/// Centralizes parsing so it can be unit-tested with a supplied dictionary,
/// and reused anywhere the running app's identity needs to be displayed.
struct AppInfo {
    /// The user-facing application name.
    let name: String
    /// Marketing version (`CFBundleShortVersionString`), e.g. `1.0.0`.
    let version: String
    /// Build number (`CFBundleVersion`).
    let build: String
    /// Short git commit hash injected at build time via `AppBuildHash`.
    let commitHash: String

    init(info: [String: Any]?) {
        name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "ShatterBreak"
        version = info?["CFBundleShortVersionString"] as? String ?? "—"
        build = info?["CFBundleVersion"] as? String ?? "—"
        commitHash = info?["AppBuildHash"] as? String ?? "dev"
    }

    /// Metadata for the currently running application.
    static let current = AppInfo(info: Bundle.main.infoDictionary)
}
