import SwiftUI

/// The menu's caution that a timer transition came due but could not fire, above the two
/// things worth doing about it: resume, and report.
///
/// Styled on ``PermissionWarningView`` so the app's cautions read alike, but it carries two
/// actions rather than one because the two are independent — resuming fixes this
/// occurrence, reporting is what makes the next one preventable. Resume comes first: the
/// user opened the menu to get their timer back, not to file a bug.
///
/// This lives in the menu rather than in an alert because the app raises no alerts of its
/// own, and because the menu is where the user goes once they notice nothing is happening —
/// the menu bar timer is hidden by default, so there is no 00:00 on screen to see.
struct StalledTimerWarningView: View {
    let report: StalledTransitionReport
    let onResume: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading) {
            WarningLabel(message: .stalledTimerWarning)

            Text(.stalledTimerStuckDuration(report.formattedAsleepDuration))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button(.stalledTimerResetAction, action: onResume)

                if let reportURL = report.reportURL {
                    Button(.stalledTimerReportAction) { openURL(reportURL) }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Stalled during work") {
    StalledTimerWarningView(
        report: StalledTransitionReport(mode: .running, asleepSecs: 1_500),
        onResume: { }
    )
    .padding()
    .frame(width: 320)
}

#Preview("Stalled during a break") {
    StalledTimerWarningView(
        report: StalledTransitionReport(mode: .resting, asleepSecs: 240),
        onResume: { }
    )
    .padding()
    .frame(width: 320)
}
