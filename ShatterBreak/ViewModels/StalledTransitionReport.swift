import Foundation

/// A timer transition that came due but could not fire, and the diagnostics needed to
/// report it.
///
/// Pulled out as a pure value (like ``WakeOutcome``) so both the detection rule and the
/// prefilled issue URL can be unit-tested without driving ``TimerState`` or opening a
/// browser.
///
/// The stall this describes is the issue #87 family: a `sleptAt` that no wake ever cleared
/// keeps ``TimerState/handleCountdownExpiryIfNeeded()`` from firing, so the countdown sits
/// at 00:00 and every later transition is dropped too. Issue #89 tracks whether the app
/// should heal that on its own; until then, reporting it accurately is what turns a vague
/// "it got stuck again" into something actionable.
struct StalledTransitionReport: Equatable {
    /// The mode the timer was stuck in — which transition was owed.
    let mode: TimerState.Mode
    /// How long the asleep flag has been set. Stands in for how long the timer has been
    /// stuck: the flag is set at or before the expiry it goes on to block.
    let asleepSecs: TimeInterval
    let appVersion: String
    let appBuild: String
    let commitHash: String

    init(
        mode: TimerState.Mode,
        asleepSecs: TimeInterval,
        appInfo: AppInfo = .current
    ) {
        self.mode = mode
        self.asleepSecs = asleepSecs
        self.appVersion = appInfo.version
        self.appBuild = appInfo.build
        self.commitHash = appInfo.commitHash
    }

    /// The stuck duration, rounded for display and for the report body.
    var formattedAsleepDuration: String {
        Duration.seconds(Int(asleepSecs.rounded()))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// A new-issue URL on the tracker, prefilled with everything a report needs.
    ///
    /// A fresh issue rather than a comment on #89: each occurrence carries its own
    /// diagnostics, and #89 stays the design discussion rather than a log of sightings.
    var reportURL: URL? {
        var components = URLComponents(string: "https://github.com/alipovoy/ShatterBreak/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Timer stalled at 00:00 in \(String(describing: mode)) mode"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: issueBody)
        ]
        return components?.url
    }

    /// The prefilled issue body. Everything here is machine-collected: the point of the
    /// report is that it does not depend on remembering what happened.
    private var issueBody: String {
        """
        The app detected a timer transition that came due but could not fire, and offered \
        a reset. This is the issue #87 family, tracked for hardening in #89.

        ### Detected state

        | | |
        |---|---|
        | Mode | `\(String(describing: mode))` |
        | Stuck for | \(formattedAsleepDuration) |
        | Version | \(appVersion) (\(appBuild)) |
        | Commit | `\(commitHash)` |

        ### What this means

        A sleep notification arrived without a matching wake, so `sleptAt` stayed set and \
        blocked `handleCountdownExpiryIfNeeded()`. The countdown sat at 00:00 and every \
        transition after it would have been dropped too.

        ### What I was doing

        <!-- Anything unusual before this: closing the lid, an external display, \
        fast user switching, force quit? -->
        """
    }
}
