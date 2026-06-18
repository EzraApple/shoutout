import Combine
import Foundation

public struct UsageStatsSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var finalText: String
    public var duration: TimeInterval
    public var model: String
    public var wordCount: Int
    public var wordsPerMinute: Int
    public var performance: UsagePerformanceMetrics?

    public init(
        id: UUID = UUID(),
        date: Date,
        finalText: String,
        duration: TimeInterval,
        model: String,
        wordCount: Int,
        wordsPerMinute: Int,
        performance: UsagePerformanceMetrics? = nil
    ) {
        self.id = id
        self.date = date
        self.finalText = finalText
        self.duration = duration
        self.model = model
        self.wordCount = wordCount
        self.wordsPerMinute = wordsPerMinute
        self.performance = performance
    }
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

    private let fileURL: URL

    public var recentSessions: [UsageStatsSession] {
        sessions.sorted { $0.date > $1.date }
    }

    public var todaySummary: UsageStatsSummary {
        summarize(sessions.filter { Calendar.current.isDateInToday($0.date) })
    }

    public var allTimeSummary: UsageStatsSummary {
        summarize(sessions)
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.sessions = Self.loadSessions(fileURL: fileURL)
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
                finalText: normalizedText,
                duration: safeDuration,
                model: model,
                wordCount: wordCount,
                wordsPerMinute: wordsPerMinute,
                performance: performance
            )
        )

        try save()
    }

    public func clear() throws {
        sessions = []
        try save()
    }

    private func summarize(_ sessions: [UsageStatsSession]) -> UsageStatsSummary {
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
            averagePressToRecordStartMs: averageInt(
                performanceMetrics.compactMap(\.pressToRecordStartMs)
            ),
            averageStopToPasteMs: averageInt(performanceMetrics.compactMap(\.stopToPasteMs)),
            averageTranscriptionWallMs: averageInt(
                performanceMetrics.compactMap(\.transcriptionWallMs)
            ),
            averageRealTimeFactor: averageDouble(
                performanceMetrics.compactMap(\.realTimeFactor)
            )
        )
    }

    private func averageInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int(round(Double(values.reduce(0, +)) / Double(values.count)))
    }

    private func averageDouble(_ values: [Double]) -> Double? {
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
