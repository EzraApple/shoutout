import Combine
import Foundation

public enum DictionaryStoreError: LocalizedError {
    case emptyPhrase
    case missingEntry

    public var errorDescription: String? {
        switch self {
        case .emptyPhrase:
            return "Dictionary phrase cannot be empty"
        case .missingEntry:
            return "Dictionary entry was not found"
        }
    }
}

public final class DictionaryStore: ObservableObject {
    @Published public private(set) var entries: [DictionaryEntry]

    private let fileURL: URL
    private let defaultEntries: [DictionaryEntry]

    public init(
        fileURL: URL,
        defaultEntries: [DictionaryEntry] = DictionaryEntry.defaultEntries
    ) {
        self.fileURL = fileURL
        self.defaultEntries = defaultEntries
        self.entries = Self.loadEntries(fileURL: fileURL, defaultEntries: defaultEntries)
    }

    public static func defaultStore(bundleIdentifier: String? = Bundle.main.bundleIdentifier)
        -> DictionaryStore
    {
        DictionaryStore(fileURL: defaultFileURL(bundleIdentifier: bundleIdentifier))
    }

    public static func defaultFileURL(bundleIdentifier: String?) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundleID = bundleIdentifier ?? "com.ezraapple.shoutout"
        return appSupport
            .appendingPathComponent(bundleID)
            .appendingPathComponent("dictionary.json")
    }

    public func addEntry(phrase: String, aliasesText: String) throws {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPhrase.isEmpty else {
            throw DictionaryStoreError.emptyPhrase
        }

        let aliases = Self.parseAliases(aliasesText)
        if let index = entries.firstIndex(where: {
            $0.phrase.compare(normalizedPhrase, options: .caseInsensitive) == .orderedSame
        }) {
            entries[index].phrase = normalizedPhrase
            entries[index].aliases = aliases
        } else {
            entries.append(DictionaryEntry(phrase: normalizedPhrase, aliases: aliases))
        }
        try save()
    }

    public func updateEntry(id: UUID, phrase: String, aliasesText: String) throws {
        let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPhrase.isEmpty else {
            throw DictionaryStoreError.emptyPhrase
        }
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw DictionaryStoreError.missingEntry
        }

        entries[index].phrase = normalizedPhrase
        entries[index].aliases = Self.parseAliases(aliasesText)
        try save()
    }

    public func deleteEntry(id: UUID) throws {
        entries.removeAll { $0.id == id }
        try save()
    }

    public func resetToDefaults() throws {
        entries = defaultEntries
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadEntries(
        fileURL: URL,
        defaultEntries: [DictionaryEntry]
    ) -> [DictionaryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
            let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else {
            return defaultEntries
        }
        return entries
    }

    private static func parseAliases(_ aliasesText: String) -> [String] {
        var seenAliases: Set<String> = []

        return aliasesText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { alias in
                let key = alias.lowercased()
                guard !seenAliases.contains(key) else {
                    return false
                }
                seenAliases.insert(key)
                return true
            }
    }
}
