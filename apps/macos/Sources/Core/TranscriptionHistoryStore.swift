import Combine
import Foundation

public struct TranscriptionHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var text: String
    public var wordCount: Int
    public var duration: TimeInterval
    public var model: String

    public init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        wordCount: Int,
        duration: TimeInterval,
        model: String
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.wordCount = wordCount
        self.duration = duration
        self.model = model
    }
}

public final class TranscriptionHistoryStore: ObservableObject {
    @Published public private(set) var entries: [TranscriptionHistoryEntry]

    private let fileURL: URL
    private let maxEntries: Int

    public var recentEntries: [TranscriptionHistoryEntry] {
        entries.sorted { $0.date > $1.date }
    }

    public init(fileURL: URL, maxEntries: Int = 200) {
        self.fileURL = fileURL
        self.maxEntries = max(1, maxEntries)
        self.entries = Self.loadEntries(fileURL: fileURL)
            .sorted { $0.date > $1.date }
            .prefix(self.maxEntries)
            .map { $0 }
    }

    public static func defaultStore(bundleIdentifier: String? = Bundle.main.bundleIdentifier)
        -> TranscriptionHistoryStore
    {
        TranscriptionHistoryStore(fileURL: defaultFileURL(bundleIdentifier: bundleIdentifier))
    }

    public static func defaultFileURL(bundleIdentifier: String?) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundleID = bundleIdentifier ?? "com.ezraapple.shoutout"
        return appSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent("transcription-history.json")
    }

    public func record(
        text: String,
        duration: TimeInterval,
        date: Date = Date(),
        model: String
    ) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        entries.insert(
            TranscriptionHistoryEntry(
                date: date,
                text: normalizedText,
                wordCount: Self.countWords(in: normalizedText),
                duration: max(duration, 0),
                model: model
            ),
            at: 0
        )
        entries = Array(entries.prefix(maxEntries))
        try save()
    }

    public func clear() throws {
        entries = []
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadEntries(fileURL: URL) -> [TranscriptionHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TranscriptionHistoryEntry].self, from: data)) ?? []
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
