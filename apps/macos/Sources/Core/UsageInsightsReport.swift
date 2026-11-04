import Foundation

public enum UsageInsightsRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case allTime

    public var id: Self { self }

    public var label: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .allTime: "All time"
        }
    }

    public var dayCount: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .allTime: nil
        }
    }
}

public struct UsageInsightsReport: Sendable {
    public struct Summary: Sendable {
        public let wordCount: Int
        public let sessionCount: Int
        public let totalDuration: TimeInterval
        public let averageWordsPerMinute: Int?

        fileprivate init(sessions: [UsageStatsSession]) {
            wordCount = sessions.reduce(0) { total, session in
                let (sum, overflow) = total.addingReportingOverflow(session.wordCount)
                return overflow ? Int.max : sum
            }
            sessionCount = sessions.count
            totalDuration = sessions.reduce(0) { $0 + $1.duration }
            let pace = (Double(wordCount) / totalDuration * 60).rounded()
            averageWordsPerMinute = totalDuration > 0 && pace.isFinite
                ? (pace >= Double(Int.max) ? Int.max : Int(pace))
                : nil
        }
    }

    public enum BucketUnit: Sendable {
        case day
        case week
        case month
    }

    public struct Bucket: Identifiable, Sendable {
        public let start: Date
        public let end: Date
        public let wordCount: Int
        public let sessionCount: Int
        public let isCurrent: Bool

        public var id: Date { start }
        public var date: Date { start }
    }

    public enum DayPart: String, CaseIterable, Sendable {
        case morning
        case afternoon
        case evening
        case night

        public var label: String { rawValue.capitalized }

        fileprivate init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<22: self = .evening
            default: self = .night
            }
        }
    }

    public let range: UsageInsightsRange
    public let periodStart: Date
    public let periodEnd: Date
    public let summary: Summary
    public let previousSummary: Summary?
    public let bucketUnit: BucketUnit
    public let buckets: [Bucket]
    public let medianDuration: Double?
    public let medianWordCount: Double?
    public let mostActiveWeekday: Int?
    public let mostActiveDayPart: DayPart?

    public init(
        sessions: [UsageStatsSession],
        range: UsageInsightsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.range = range
        let validSessions = sessions.filter {
            $0.date.timeIntervalSinceReferenceDate.isFinite
                && $0.date <= now && $0.wordCount >= 0 && $0.duration > 0
                && $0.duration.isFinite
        }
        let today = calendar.startOfDay(for: now)
        let start: Date
        if let dayCount = range.dayCount {
            start = calendar.date(byAdding: .day, value: 1 - dayCount, to: today)!
        } else {
            start = calendar.startOfDay(for: validSessions.map(\.date).min() ?? now)
        }
        periodStart = start
        periodEnd = now

        let selected = validSessions.filter { $0.date >= start }
        summary = Summary(sessions: selected)
        if let dayCount = range.dayCount {
            let previousStart = calendar.date(byAdding: .day, value: -dayCount, to: start)!
            previousSummary = Summary(sessions: validSessions.filter {
                $0.date >= previousStart && $0.date < start
            })
        } else {
            previousSummary = nil
        }

        let unit: BucketUnit
        if range != .allTime || calendar.dateComponents([.day], from: start, to: today).day! < 31 {
            unit = .day
        } else {
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)!.start
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let weeks = calendar.dateComponents([.weekOfYear], from: firstWeek, to: currentWeek).weekOfYear!
            unit = weeks < 26 ? .week : .month
        }
        bucketUnit = unit
        let component: Calendar.Component = switch unit {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        let firstBucket = calendar.dateInterval(of: component, for: start)!.start
        let currentBucket = calendar.dateInterval(of: component, for: now)!.start
        var counts: [Date: (words: Int, sessions: Int)] = [:]
        for session in selected {
            let bucketStart = calendar.dateInterval(of: component, for: session.date)!.start
            var count = counts[bucketStart] ?? (0, 0)
            let (words, overflow) = count.words.addingReportingOverflow(session.wordCount)
            count.words = overflow ? Int.max : words
            count.sessions += 1
            counts[bucketStart] = count
        }
        var filledBuckets: [Bucket] = []
        var bucketStart = firstBucket
        while bucketStart <= currentBucket {
            let bucketEnd = calendar.date(byAdding: component, value: 1, to: bucketStart)!
            let count = counts[bucketStart] ?? (0, 0)
            filledBuckets.append(Bucket(
                start: bucketStart,
                end: bucketEnd,
                wordCount: count.words,
                sessionCount: count.sessions,
                isCurrent: bucketStart == currentBucket
            ))
            bucketStart = bucketEnd
        }
        buckets = filledBuckets

        let activeDays = Set(selected.map { calendar.startOfDay(for: $0.date) })
        if selected.count >= 10 && activeDays.count >= 5 {
            medianDuration = Self.median(selected.map(\.duration))
            medianWordCount = Self.median(selected.map { Double($0.wordCount) })
            mostActiveWeekday = Self.mostActiveCategory(selected) {
                calendar.component(.weekday, from: $0.date)
            }
            mostActiveDayPart = Self.mostActiveCategory(selected) {
                DayPart(hour: calendar.component(.hour, from: $0.date))
            }
        } else {
            medianDuration = nil
            medianWordCount = nil
            mostActiveWeekday = nil
            mostActiveDayPart = nil
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? sorted[middle - 1] / 2 + sorted[middle] / 2
            : sorted[middle]
    }

    private static func mostActiveCategory<Category: Hashable>(
        _ sessions: [UsageStatsSession],
        category: (UsageStatsSession) -> Category
    ) -> Category {
        var frequency: [Category: (count: Int, latest: Date)] = [:]
        for session in sessions {
            let key = category(session)
            let previous = frequency[key]
            frequency[key] = ((previous?.count ?? 0) + 1, max(previous?.latest ?? session.date, session.date))
        }
        return frequency.max {
            $0.value.count == $1.value.count
                ? $0.value.latest < $1.value.latest
                : $0.value.count < $1.value.count
        }!.key
    }
}
