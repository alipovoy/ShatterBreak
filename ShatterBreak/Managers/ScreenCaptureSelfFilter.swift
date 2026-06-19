import Foundation

/// Decides whether a running application is ShatterBreak itself.
///
/// ScreenCaptureKit must exclude the app's own windows from captured screenshots,
/// otherwise the overlay would be painted on top of its own freeze-frame. The
/// predicate is factored out as a pure function so the self-filtering rule can be
/// unit tested without constructing `SCRunningApplication`, which has no public
/// initializer.
enum ScreenCaptureSelfFilter {
    /// Whether the described application is the current process.
    ///
    /// A match on the process identifier is authoritative. Otherwise, the bundle
    /// identifier is compared so helper processes sharing the app's bundle are
    /// also excluded.
    static func isSelf(
        processID: pid_t,
        bundleIdentifier: String?,
        currentProcessID: pid_t,
        currentBundleIdentifier: String?
    ) -> Bool {
        if processID == currentProcessID {
            return true
        }

        guard let currentBundleIdentifier else { return false }
        return bundleIdentifier == currentBundleIdentifier
    }
}
