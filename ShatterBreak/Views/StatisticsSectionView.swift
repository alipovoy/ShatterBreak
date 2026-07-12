import SwiftUI

/// The collapsible statistics tally in the menu (issue #10): four counters, the moment
/// the tally began, and a manual reset. Shown only while "Track statistics" is enabled.
struct StatisticsSectionView: View {
    let statistics: StatisticsStore

    @AppStorage(PreferenceKeys.statisticsExpanded)
    private var isExpanded = PreferenceDefaults.statisticsExpanded

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                row(.statisticsWorkSessions, count: statistics.current.workSessionsCompleted)
                row(.statisticsBreaks, count: statistics.current.breaksCompleted)
                row(.statisticsPostponed, count: statistics.current.postponesUsed)
                row(.statisticsEarlyReturns, count: statistics.current.earlyReturns)

                HStack {
                    Text(.statisticsSince(sinceText))
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button(.resetStatistics, systemImage: "arrow.counterclockwise") {
                        statistics.reset()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(IconButtonStyle())
                    .help(Text(.resetStatisticsHelp))
                }
            }
            .padding(.top, 8)
        } label: {
            Label(.statistics, systemImage: "chart.bar.xaxis")
        }
    }

    private func row(_ title: LocalizedStringResource, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    /// A same-day tally shows just the time; an older one adds the date so a
    /// long-running tally is not mistaken for today's.
    private var sinceText: String {
        let since = statistics.current.since
        if Calendar.current.isDateInToday(since) {
            return since.formatted(date: .omitted, time: .shortened)
        }
        return since.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview("StatisticsSectionView") { @MainActor in
    StatisticsSectionView(statistics: StatisticsStore())
        .padding()
        .frame(width: 320)
}
