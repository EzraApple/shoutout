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

    public init(
        id: UUID = UUID(),
        date: Date,
        finalText: String,
        duration: TimeInterval,
        model: String,
        wordCount: Int,
        wordsPerMinute: Int
    ) {
        self.id = id
        self.date = date
        self.finalText = finalText
        self.duration = duration
        self.model = model
        self.wordCount = wordCount
        self.wordsPerMinute = wordsPerMinute
    }
}

public struct UsageStatsSummary: Equatable, Sendable {
    public var sessionCount: Int
    public var wordCount: Int
    public var totalDuration: TimeInterval
    public var averageWordsPerMinute: Int

    public static let empty = UsageStatsSummary(
        sessionCount: 0,
        wordCount: 0,
        totalDuration: 0,
        averageWordsPerMinute: 0
    )
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
        model: String
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
                wordsPerMinute: wordsPerMinute
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

        return UsageStatsSummary(
            sessionCount: sessions.count,
            wordCount: wordCount,
            totalDuration: totalDuration,
            averageWordsPerMinute: averageWordsPerMinute
        )
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
