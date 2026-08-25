import Foundation

/// A timer transition that came due but never fired, and the diagnostics needed to
/// report it.
///
/// A pure value (like ``WakeOutcome``) so both the detection rule and the prefilled issue
/// URL can be unit-tested without driving ``TimerState`` or opening a browser.
///
/// Detection is keyed to the symptom, so the cause is unknown by construction:
/// ``wasAsleep`` is what lets a filed report be classified after the fact.
struct StalledTransitionReport: Equatable {
    /// The mode the timer was stuck in — which transition was owed.
    let mode: TimerState.Mode
    /// How far past its deadline the owed transition is.
    let overdueSecs: TimeInterval
    /// Whether the asleep flag was still set. Set means the issue #87 family — a sleep
    /// whose wake never arrived; clear means the expiry was lost some other way.
    let wasAsleep: Bool
    let appVersion: String
    let appBuild: String
    let commitHash: String

    init(
        mode: TimerState.Mode,
        overdueSecs: TimeInterval,
        wasAsleep: Bool,
        appInfo: AppInfo = .current
    ) {
        self.mode = mode
        self.overdueSecs = overdueSecs
        self.wasAsleep = wasAsleep
        self.appVersion = appInfo.version
        self.appBuild = appInfo.build
        self.commitHash = appInfo.commitHash
    }

    /// The stuck duration, rounded for display and for the report body.
    var formattedOverdue: String {
        Duration.seconds(Int(overdueSecs.rounded()))
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

    /// What the asleep flag says about which failure this was.
    private var causeNote: String {
        wasAsleep
            ? "The asleep flag was still set: a sleep notification arrived without a matching "
                + "wake, which is the issue #87 family."
            : "The asleep flag was clear, so this is not the issue #87 family — the expiry was "
                + "lost some other way."
    }

    /// The prefilled issue body. Everything here is machine-collected: the point of the
    /// report is that it does not depend on remembering what happened.
    private var issueBody: String {
        """
        The app detected a timer transition that came due but never fired, and offered a \
        reset. Hardening for this is tracked in #89.

        ### Detected state

        | | |
        |---|---|
        | Mode | `\(String(describing: mode))` |
        | Overdue by | \(formattedOverdue) |
        | Asleep flag | \(wasAsleep ? "stuck" : "clear") |
        | Version | \(appVersion) (\(appBuild)) |
        | Commit | `\(commitHash)` |

        ### What this means

        The countdown passed its deadline and the transition it owed never ran, so the \
        timer sat at 00:00 and every transition after it would have been dropped too. \
        \(causeNote)

        ### What I was doing

        <!-- Anything unusual before this: closing the lid, an external display, \
        fast user switching, force quit? -->
        """
    }
}
