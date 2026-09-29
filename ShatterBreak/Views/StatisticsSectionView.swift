import SwiftUI

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

    /// An older tally adds the date, so it is not mistaken for today's.
    private var sinceText: String {
        let since = statistics.current.since
        if Calendar.current.isDateInToday(since) {
            return since.formatted(date: .omitted, time: .shortened)
        }
        return since.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview("StatisticsSectionView") { @MainActor in
    let defaults = InMemoryKeyValueStore()
    defaults.set(true, forKey: PreferenceKeys.trackStatistics)
    let statistics = StatisticsStore(defaults: defaults)
    for _ in 0..<4 { statistics.record(.workSessionCompleted) }
    for _ in 0..<3 { statistics.record(.breakCompleted) }
    statistics.record(.postponed)
    statistics.record(.earlyReturn)

    return StatisticsSectionView(statistics: statistics)
        .padding()
        .frame(width: 320)
}
