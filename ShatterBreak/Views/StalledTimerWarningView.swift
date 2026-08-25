import SwiftUI

/// The menu's caution that a timer transition came due but never fired, above the two
/// things worth doing about it.
///
/// Styled on ``PermissionWarningView``, but with two actions rather than one because they
/// are independent: resuming fixes this occurrence, reporting is what makes the next one
/// preventable. Resume comes first — the user opened the menu to get their timer back.
///
/// Lives in the menu rather than an alert because the app raises no alerts of its own, and
/// because the menu bar timer is hidden by default, so there is no 00:00 on screen to see.
struct StalledTimerWarningView: View {
    let report: StalledTransitionReport
    let onResume: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading) {
            WarningLabel(message: .stalledTimerWarning)

            Text(.stalledTimerOverdueDuration(report.formattedOverdue))
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
        report: StalledTransitionReport(mode: .running, overdueSecs: 1_500, wasAsleep: true),
        onResume: { }
    )
    .padding()
    .frame(width: 320)
}

#Preview("Stalled during a break") {
    StalledTimerWarningView(
        report: StalledTransitionReport(mode: .resting, overdueSecs: 240, wasAsleep: false),
        onResume: { }
    )
    .padding()
    .frame(width: 320)
}
