import SwiftUI
import ShoutOutCore

struct ReviewInsightsView: View {
    @EnvironmentObject private var usageStats: UsageStatsStore
    @Binding var range: UsageInsightsRange
    let tint: Color

    var body: some View {
        let report = UsageInsightsReport(sessions: usageStats.sessions, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    ReviewPageHeader(title: "Insights")
                    Spacer(minLength: 16)
                    Picker("Insights date range", selection: $range) {
                        ForEach(UsageInsightsRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 246)
                }

                metrics(report)
                activityChart(report)
                rhythm(report)

                Text("Current streak \(dayCountText(usageStats.insights.currentStreakDays)) · Longest \(dayCountText(usageStats.insights.longestStreakDays)) · All time")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
            }
            .padding(20)
            .frame(maxWidth: ReviewTheme.detailWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .reviewWorkspaceSurface()
    }

    private func metrics(_ report: UsageInsightsReport) -> some View {
        let current = report.summary
        let previous = report.previousSummary.flatMap { current.sessionCount > 0 && $0.sessionCount > 0 ? $0 : nil }
        let showComparison = previous != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                metric("Words", value: current.wordCount.formatted(),
                       comparison: previous.map { comparison(Double(current.wordCount), previous: Double($0.wordCount)) })
                metric("Dictations", value: current.sessionCount.formatted(),
                       comparison: previous.map { comparison(Double(current.sessionCount), previous: Double($0.sessionCount)) })
                metric("Speaking time", value: durationText(current.totalDuration),
                       comparison: previous.map { comparison(current.totalDuration, previous: $0.totalDuration, duration: true) })
                metric("Average pace", value: current.averageWordsPerMinute.map { "\($0) WPM" } ?? "—",
                       comparison: current.averageWordsPerMinute.flatMap { pace in
                            previous?.averageWordsPerMinute.map { comparison(Double(pace), previous: Double($0), unit: "WPM") }
                       })
            }
            if current.sessionCount > 0, let count = range.dayCount {
                Text(showComparison ? "Compared with the previous \(count) days" : "No earlier data to compare")
                    .font(.system(size: 13))
                    .foregroundStyle(ReviewTheme.muted)
            }
        }
    }

    private func metric(_ title: String, value: String, comparison: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
            Text(value)
                .font(.system(size: 23, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ReviewTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let comparison {
                Text(comparison).font(.system(size: 13)).monospacedDigit()
                    .foregroundStyle(ReviewTheme.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func activityChart(_ report: UsageInsightsReport) -> some View {
        let buckets = report.buckets
        let maximum = max(buckets.map(\.wordCount).max() ?? 0, 1)
        let unit = bucketUnitText(report)
        let peak = buckets.max { $0.wordCount < $1.wordCount }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Words per \(unit)").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(range == .allTime ? "All time" : "Last \(range.dayCount ?? 30) calendar days")
                    .font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
            }
            if report.summary.sessionCount == 0 {
                VStack(spacing: 0) {
                    Text(range == .allTime ? "Your activity will appear after your first dictation." : "No dictations in the last \(range.dayCount ?? 30) days.")
                        .font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(ReviewTheme.line).frame(height: 1)
                }
                .frame(height: 150)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(buckets) { bucket in
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(tint.opacity(bucket.isCurrent ? 1 : 0.40))
                                    .frame(width: min(48, geometry.size.width), height: bucket.wordCount == 0 ? 0 : max(2, geometry.size.height * CGFloat(bucket.wordCount) / CGFloat(maximum)))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .help("\(bucketLabel(bucket.date, report: report)) · \(bucket.wordCount.formatted()) words · \(bucket.sessionCount) \(bucket.sessionCount == 1 ? "dictation" : "dictations")")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(bucketLabel(bucket.date, report: report))
                        .accessibilityValue("\(bucket.wordCount.formatted()) words, \(bucket.sessionCount) \(bucket.sessionCount == 1 ? "dictation" : "dictations")")
                    }
                }
                .frame(height: 150)
                .overlay(alignment: .bottom) { Rectangle().fill(ReviewTheme.line).frame(height: 1) }
                chartDateLabels(report)
            }
            if report.summary.sessionCount > 0 {
                HStack {
                    Text(peak.map { "Peak \($0.wordCount.formatted()) words" } ?? "Peak —")
                    Spacer()
                    Text("\(currentBucketText(report)) \(buckets.first(where: \.isCurrent)?.wordCount.formatted() ?? "0")")
                }
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(ReviewTheme.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(report.summary.sessionCount == 0
            ? "Words per \(unit), \(range.label.lowercased()). No dictations."
            : "Words per \(unit), \(range.label.lowercased()). Peak \(peak?.wordCount ?? 0) words\(peak.map { " on \(bucketLabel($0.date, report: report))" } ?? "").")
    }

    private func chartDateLabels(_ report: UsageInsightsReport) -> some View {
        GeometryReader { geometry in
            let count = report.buckets.count
            let width = max(0, (geometry.size.width - CGFloat(max(count - 1, 0)) * 4) / CGFloat(max(count, 1)))
            let indices = Array(Set([0, count / 2, max(count - 1, 0)])).sorted()
            ForEach(indices, id: \.self) { index in
                if index < count {
                    let center = width / 2 + CGFloat(index) * (width + 4)
                    Text(bucketLabel(report.buckets[index].date, report: report))
                        .font(.system(size: 13)).monospacedDigit().foregroundStyle(ReviewTheme.muted)
                        .lineLimit(1).frame(width: 90, alignment: index == 0 ? .leading : index == count - 1 ? .trailing : .center)
                        .position(x: min(max(center, 45), geometry.size.width - 45), y: 7)
                }
            }
        }.frame(height: 14)
    }

    private func rhythm(_ report: UsageInsightsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Typical dictation").font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
                    Text(report.medianDuration.map { "\(durationText($0)) · \(Int((report.medianWordCount ?? 0).rounded())) words" } ?? "—")
                        .font(.system(size: 17))
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Most active").font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
                    Text(activityPattern(report)).font(.system(size: 17))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if report.medianDuration == nil {
                Text("More dictations will reveal a pattern.")
                    .font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityPattern(_ report: UsageInsightsReport) -> String {
        guard let weekday = report.mostActiveWeekday, let dayPart = report.mostActiveDayPart else { return "—" }
        let day = Calendar.current.weekdaySymbols[weekday - 1]
        return "\(day)s · \(dayPart.rawValue.capitalized)s"
    }

    private func comparison(_ current: Double, previous: Double, duration: Bool = false, unit: String? = nil) -> String {
        let change = current - previous
        if change == 0 { return "No change" }
        let sign = change >= 0 ? "+" : "−"
        let value = duration ? durationText(abs(change)) : Int(abs(change).rounded()).formatted()
        let percent = previous >= 1 ? " (\(sign)\(Int((abs(change) / previous * 100).rounded()))%)" : ""
        return "\(sign)\(value)\(unit.map { " \($0)" } ?? "")\(percent)"
    }

    private func dayCountText(_ count: Int) -> String { "\(count) \(count == 1 ? "day" : "days")" }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    private func bucketUnitText(_ report: UsageInsightsReport) -> String {
        switch report.bucketUnit { case .day: "day"; case .week: "week"; case .month: "month" }
    }

    private func currentBucketText(_ report: UsageInsightsReport) -> String {
        switch report.bucketUnit { case .day: "Today"; case .week: "This week"; case .month: "This month" }
    }

    private func bucketLabel(_ date: Date, report: UsageInsightsReport) -> String {
        report.bucketUnit == .month ? date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
