import Combine
import Foundation

public struct UsageStatsSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var duration: TimeInterval
    public var model: String
    public var wordCount: Int
    public var wordsPerMinute: Int
    public var performance: UsagePerformanceMetrics?

    public init(
        id: UUID = UUID(),
        date: Date,
        duration: TimeInterval,
        model: String,
        wordCount: Int,
        wordsPerMinute: Int,
        performance: UsagePerformanceMetrics? = nil
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.model = model
        self.wordCount = wordCount
        self.wordsPerMinute = wordsPerMinute
        self.performance = performance
    }
}

public struct UsageDailySummary: Codable, Equatable, Identifiable, Sendable {
    public var date: Date
    public var sessionCount: Int
    public var wordCount: Int
    public var totalDuration: TimeInterval
    public var averageWordsPerMinute: Int

    public var id: Date { date }
}

public struct UsageInsights: Equatable, Sendable {
    public var days: [UsageDailySummary]
    public var currentStreakDays: Int
    public var longestStreakDays: Int
    public var bestDayWordCount: Int
    public var averageWordsPerActiveDay: Int

    public static let empty = UsageInsights(
        days: [],
        currentStreakDays: 0,
        longestStreakDays: 0,
        bestDayWordCount: 0,
        averageWordsPerActiveDay: 0
    )
}

public struct UsageStatsSummary: Equatable, Sendable {
    public var sessionCount: Int
    public var wordCount: Int
    public var totalDuration: TimeInterval
    public var averageWordsPerMinute: Int
    public var averagePressToRecordStartMs: Int?
    public var averageStopToPasteMs: Int?
    public var averageTranscriptionWallMs: Int?
    public var averageRealTimeFactor: Double?

    public static let empty = UsageStatsSummary(
        sessionCount: 0,
        wordCount: 0,
        totalDuration: 0,
        averageWordsPerMinute: 0,
        averagePressToRecordStartMs: nil,
        averageStopToPasteMs: nil,
        averageTranscriptionWallMs: nil,
        averageRealTimeFactor: nil
    )
}

public struct UsagePerformanceMetrics: Codable, Equatable, Sendable {
    public var inputMode: String
    public var pressToRecordStartMs: Int?
    public var pressToCommitMs: Int?
    public var recordStartRequestToReadyMs: Int?
    public var stopToSamplesMs: Int?
    public var stopToPasteMs: Int?
    public var queueWaitMs: Int?
    public var transcriptionWallMs: Int?
    public var recordingMs: Int
    public var modelWaitMs: Int
    public var whisperWallMs: Int
    public var postProcessMs: Int
    public var firstTokenMs: Int?
    public var whisperPipelineMs: Int?
    public var realTimeFactor: Double?
    public var speedFactor: Double?
    public var tokensPerSecond: Double?
    public var fallbackCount: Int?
    public var languagePassEnabled: Bool?
    public var languagePassAccepted: Bool?
    public var languagePassChanged: Bool?
    public var languagePassWallMs: Int?
    public var languagePassModel: String?
    public var languagePassFallbackReason: String?

    public init(
        inputMode: String,
        pressToRecordStartMs: Int?,
        pressToCommitMs: Int?,
        recordStartRequestToReadyMs: Int?,
        stopToSamplesMs: Int?,
        stopToPasteMs: Int?,
        queueWaitMs: Int?,
        transcriptionWallMs: Int?,
        recordingMs: Int,
        modelWaitMs: Int,
        whisperWallMs: Int,
        postProcessMs: Int,
        firstTokenMs: Int?,
        whisperPipelineMs: Int?,
        realTimeFactor: Double?,
        speedFactor: Double?,
        tokensPerSecond: Double?,
        fallbackCount: Int?,
        languagePassEnabled: Bool? = nil,
        languagePassAccepted: Bool? = nil,
        languagePassChanged: Bool? = nil,
        languagePassWallMs: Int? = nil,
        languagePassModel: String? = nil,
        languagePassFallbackReason: String? = nil
    ) {
        self.inputMode = inputMode
        self.pressToRecordStartMs = pressToRecordStartMs
        self.pressToCommitMs = pressToCommitMs
        self.recordStartRequestToReadyMs = recordStartRequestToReadyMs
        self.stopToSamplesMs = stopToSamplesMs
        self.stopToPasteMs = stopToPasteMs
        self.queueWaitMs = queueWaitMs
        self.transcriptionWallMs = transcriptionWallMs
        self.recordingMs = recordingMs
        self.modelWaitMs = modelWaitMs
        self.whisperWallMs = whisperWallMs
        self.postProcessMs = postProcessMs
        self.firstTokenMs = firstTokenMs
        self.whisperPipelineMs = whisperPipelineMs
        self.realTimeFactor = realTimeFactor
        self.speedFactor = speedFactor
        self.tokensPerSecond = tokensPerSecond
        self.fallbackCount = fallbackCount
        self.languagePassEnabled = languagePassEnabled
        self.languagePassAccepted = languagePassAccepted
        self.languagePassChanged = languagePassChanged
        self.languagePassWallMs = languagePassWallMs
        self.languagePassModel = languagePassModel
        self.languagePassFallbackReason = languagePassFallbackReason
    }
}

public final class UsageStatsStore: ObservableObject {
    @Published public private(set) var sessions: [UsageStatsSession]
    @Published public private(set) var todaySummary: UsageStatsSummary
    @Published public private(set) var allTimeSummary: UsageStatsSummary
    @Published public private(set) var insights: UsageInsights

    private let fileURL: URL

    public var recentSessions: [UsageStatsSession] {
        sessions.sorted { $0.date > $1.date }
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let loadedSessions = Self.loadSessions(fileURL: fileURL)
        self.sessions = loadedSessions
        self.todaySummary = Self.summarize(
            loadedSessions.filter { Calendar.current.isDateInToday($0.date) }
        )
        self.allTimeSummary = Self.summarize(loadedSessions)
        self.insights = Self.buildInsights(from: loadedSessions)
    }

    public static func defaultStore(bundleIdentifier: String? = Bundle.main.bundleIdentifier)
        -> UsageStatsStore
    {
        UsageStatsStore(fileURL: defaultFileURL(bundleIdentifier: bundleIdentifier))
    }

    public static func defaultFileURL(bundleIdentifier: String?) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundleID = bundleIdentifier ?? "com.ezraapple.shoutout"
        return appSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent("usage-stats.json")
    }

    public func record(
        finalText: String,
        duration: TimeInterval,
        date: Date = Date(),
        model: String,
        performance: UsagePerformanceMetrics? = nil
    ) throws {
        let normalizedText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        let wordCount = Self.countWords(in: normalizedText)
        let safeDuration = max(duration, 1)
        let wordsPerMinute = Int(round(Double(wordCount) / safeDuration * 60))

        sessions.append(
            UsageStatsSession(
                date: date,
                duration: safeDuration,
                model: model,
                wordCount: wordCount,
                wordsPerMinute: wordsPerMinute,
                performance: performance
            )
        )

        rebuildCachedStats()
        try save()
    }

    public func clear() throws {
        sessions = []
        rebuildCachedStats()
        try save()
    }

    private func rebuildCachedStats() {
        todaySummary = Self.summarize(sessions.filter { Calendar.current.isDateInToday($0.date) })
        allTimeSummary = Self.summarize(sessions)
        insights = Self.buildInsights(from: sessions)
    }

    private static func summarize(_ sessions: [UsageStatsSession]) -> UsageStatsSummary {
        guard !sessions.isEmpty else {
            return .empty
        }

        let wordCount = sessions.reduce(0) { total, session in
            total + session.wordCount
        }
        let totalDuration = sessions.reduce(TimeInterval(0)) { total, session in
            total + session.duration
        }
        let averageWordsPerMinute = totalDuration > 0
            ? Int(round(Double(wordCount) / totalDuration * 60))
            : 0
        let performanceMetrics = sessions.compactMap(\.performance)

        return UsageStatsSummary(
            sessionCount: sessions.count,
            wordCount: wordCount,
            totalDuration: totalDuration,
            averageWordsPerMinute: averageWordsPerMinute,
            averagePressToRecordStartMs: Self.averageInt(
                performanceMetrics.compactMap(\.pressToRecordStartMs)
            ),
            averageStopToPasteMs: Self.averageInt(performanceMetrics.compactMap(\.stopToPasteMs)),
            averageTranscriptionWallMs: Self.averageInt(
                performanceMetrics.compactMap(\.transcriptionWallMs)
            ),
            averageRealTimeFactor: Self.averageDouble(
                performanceMetrics.compactMap(\.realTimeFactor)
            )
        )
    }

    private static func buildInsights(from sessions: [UsageStatsSession]) -> UsageInsights {
        guard !sessions.isEmpty else {
            return .empty
        }

        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.date)
        }
        let days = groupedByDay.map { day, sessions in
            let summary = summarize(sessions)
            return UsageDailySummary(
                date: day,
                sessionCount: summary.sessionCount,
                wordCount: summary.wordCount,
                totalDuration: summary.totalDuration,
                averageWordsPerMinute: summary.averageWordsPerMinute
            )
        }
        .sorted { $0.date < $1.date }

        let activeDates = days.map(\.date)
        let activeDateSet = Set(activeDates)
        let currentStreakDays = currentStreak(in: activeDateSet, calendar: calendar)
        let longestStreakDays = longestStreak(in: activeDates, calendar: calendar)
        let totalWords = days.reduce(0) { $0 + $1.wordCount }

        return UsageInsights(
            days: days,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            bestDayWordCount: days.map(\.wordCount).max() ?? 0,
            averageWordsPerActiveDay: days.isEmpty
                ? 0
                : Int(round(Double(totalWords) / Double(days.count)))
        )
    }

    private static func currentStreak(in activeDates: Set<Date>, calendar: Calendar) -> Int {
        guard !activeDates.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: Date())
        if !activeDates.contains(cursor),
            let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
            activeDates.contains(yesterday)
        {
            cursor = yesterday
        }

        var count = 0
        while activeDates.contains(cursor) {
            count += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return count
    }

    private static func longestStreak(in sortedDates: [Date], calendar: Calendar) -> Int {
        guard !sortedDates.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in sortedDates.indices.dropFirst() {
            let previous = sortedDates[sortedDates.index(before: index)]
            let date = sortedDates[index]
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
                calendar.isDate(date, inSameDayAs: expected)
            {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }

    private static func averageInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int(round(Double(values.reduce(0, +)) / Double(values.count)))
    }

    private static func averageDouble(_ values: [Double]) -> Double? {
        let finiteValues = values.filter(\.isFinite)
        guard !finiteValues.isEmpty else { return nil }
        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadSessions(fileURL: URL) -> [UsageStatsSession] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageStatsSession].self, from: data)) ?? []
    }

    private static func countWords(in text: String) -> Int {
        let pattern = "[\\p{L}\\p{N}]+(?:[-'][\\p{L}\\p{N}]+)*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}
