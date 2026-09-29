import Foundation

struct AppInfo {
    let name: String
    let version: String
    let build: String
    /// Injected at build time as `AppBuildHash`.
    let commitHash: String

    init(info: [String: Any]?) {
        name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "ShatterBreak"
        version = info?["CFBundleShortVersionString"] as? String ?? "—"
        build = info?["CFBundleVersion"] as? String ?? "—"
        commitHash = info?["AppBuildHash"] as? String ?? "dev"
    }

    static let current = AppInfo(info: Bundle.main.infoDictionary)
}
