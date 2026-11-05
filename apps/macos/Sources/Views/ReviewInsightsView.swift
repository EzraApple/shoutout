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
        let allTime = report.range == .allTime
        let peak = buckets.max { $0.wordsPerDay < $1.wordsPerDay }
        let current = buckets.last
        let currentLabel = allTime && (current?.dayCount ?? 1) > 1 ? "Latest period" : "Today"
        let plotInset: CGFloat = 8
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(allTime ? "Average words per day" : "Words per day")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !report.activityTrend.isEmpty {
                    HStack(spacing: 6) {
                        Capsule().fill(ReviewTheme.muted).frame(width: 14, height: 1.5)
                            .accessibilityHidden(true)
                        Text("Trend")
                    }
                    .font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
                    .help("Rolling average over up to three chart periods")
                    .accessibilityLabel("Trend, rolling average over up to three chart periods")
                } else if let days = range.dayCount {
                    Text("Last \(days) calendar days")
                        .font(.system(size: 13)).foregroundStyle(ReviewTheme.muted)
                }
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
                InsightsActivityBars(buckets: buckets, trend: report.activityTrend, showsDailyAverage: allTime, tint: tint)
                    .id(range)
                    .padding(.horizontal, plotInset)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(ReviewTheme.line).frame(height: 1)
                            .allowsHitTesting(false)
                    }
                chartDateLabels(report)
                    .padding(.horizontal, plotInset)
            }
            if report.summary.sessionCount > 0 {
                HStack {
                    Text(peak.map { "Peak \(activityValue($0, allTime: allTime))" } ?? "Peak —")
                    Spacer()
                    Text("\(currentLabel) \(current.map { activityValue($0, allTime: allTime) } ?? "—")")
                }
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(ReviewTheme.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(report.summary.sessionCount == 0
            ? "Words per day, \(range.label.lowercased()). No dictations."
            : "Words per day, \(range.label.lowercased()). Peak \(peak.map { activityValue($0, allTime: allTime) } ?? "—").")
    }

    private func chartDateLabels(_ report: UsageInsightsReport) -> some View {
        GeometryReader { geometry in
            let count = report.buckets.count
            let showsYear = report.buckets.contains { $0.dayCount >= 28 }
            let width = geometry.size.width / CGFloat(max(count, 1))
            let indices = Array(Set([0, count / 2, max(count - 1, 0)])).sorted()
            ForEach(indices, id: \.self) { index in
                if index < count {
                    let center = (CGFloat(index) + 0.5) * width
                    let date = report.buckets[index].start
                    Text(showsYear ? date.formatted(.dateTime.month(.abbreviated).year())
                         : date.formatted(.dateTime.month(.abbreviated).day()))
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

    private func activityValue(_ bucket: UsageInsightsReport.Bucket, allTime: Bool) -> String {
        allTime ? "\(dailyAverageText(bucket)) words/day" : "\(bucket.wordCount.formatted()) words"
    }
}

private struct InsightsActivityBars: View {
    @Environment(\.controlActiveState) private var activeState
    @State private var hoveredBucket: Date?

    let buckets: [UsageInsightsReport.Bucket]
    let trend: [Double]
    let showsDailyAverage: Bool
    let tint: Color

    var body: some View {
        let maximum = max(buckets.map(\.wordsPerDay).max() ?? 0, 1)
        GeometryReader { geometry in
            let width = geometry.size.width
            let columnWidth = width / CGFloat(max(buckets.count, 1))
            let barWidth = min(64, columnWidth - min(2, columnWidth * 0.2))

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(buckets) { bucket in
                    let isHovered = bucket.id == hoveredBucket
                    let opacity = bucket.isCurrent ? (isHovered ? 1 : 0.92) : (isHovered ? 0.76 : 0.40)
                    let height = geometry.size.height * CGFloat(bucket.wordsPerDay / maximum)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint.opacity(opacity))
                            .frame(width: barWidth, height: bucket.wordCount == 0 ? 0 : max(2, height))
                    }
                    .frame(width: columnWidth)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(periodLabel(bucket))
                    .accessibilityValue(bucketSummary(bucket))
                }
            }
            .overlay {
                if !trend.isEmpty {
                    Path { path in
                        for (index, value) in trend.enumerated() {
                            let point = CGPoint(x: (CGFloat(index) + 0.5) * columnWidth,
                                                y: geometry.size.height * CGFloat(1 - value / maximum))
                            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(ReviewTheme.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard columnWidth > 0, !buckets.isEmpty else { return }
                    let index = min(max(0, Int(location.x / columnWidth)), buckets.count - 1)
                    let id = buckets[index].id
                    if hoveredBucket != id { hoveredBucket = id }
                case .ended:
                    hoveredBucket = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let index = buckets.firstIndex(where: { $0.id == hoveredBucket }) {
                    let center = (CGFloat(index) + 0.5) * columnWidth
                    bucketPreview(buckets[index])
                        .visualEffect { content, proxy in
                            let gap = barWidth / 2 + 8
                            let x = center < width / 2 ? center + gap : center - gap - proxy.size.width
                            return content.offset(x: max(0, min(x, width - proxy.size.width)), y: 8)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 150)
        .onChange(of: activeState) { _, state in
            if state == .inactive { hoveredBucket = nil }
        }
    }

    private func bucketPreview(_ bucket: UsageInsightsReport.Bucket) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return VStack(alignment: .leading, spacing: 4) {
            Text(periodLabel(bucket)).font(.system(size: 13, weight: .semibold))
            Text(bucketSummary(bucket)).font(.system(size: 12)).foregroundStyle(ReviewTheme.muted)
        }
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize()
        .background(ReviewTheme.raised, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }

    private func periodLabel(_ bucket: UsageInsightsReport.Bucket) -> String {
        if bucket.dayCount == 1 {
            return bucket.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
        let lastDay = bucket.end.addingTimeInterval(-1)
        return (bucket.start..<lastDay).formatted(.interval.month(.abbreviated).day().year())
    }

    private func bucketSummary(_ bucket: UsageInsightsReport.Bucket) -> String {
        let totals = "\(bucket.wordCount.formatted()) \(bucket.wordCount == 1 ? "word" : "words") · \(bucket.sessionCount.formatted()) \(bucket.sessionCount == 1 ? "dictation" : "dictations")"
        return showsDailyAverage && bucket.dayCount > 1 ? "\(totals)\n\(dailyAverageText(bucket)) words/day" : totals
    }
}

private func dailyAverageText(_ bucket: UsageInsightsReport.Bucket) -> String {
    bucket.wordsPerDay.formatted(.number.precision(.fractionLength(0...1)))
}
