import Combine
import Foundation

public enum DictionaryStoreError: LocalizedError, Equatable {
    case emptyPhrase
    case emptyAliases
    case duplicatePhrase(String)
    case conflictingAlias(String)
    case missingEntry
    case loadFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPhrase:
            return "Write as cannot be empty."
        case .emptyAliases:
            return "Add at least one phrase to Replace."
        case .duplicatePhrase(let phrase):
            return "\"\(phrase)\" already has a dictionary entry. Edit that entry instead."
        case .conflictingAlias(let alias):
            return "\"\(alias)\" is already used by another dictionary entry."
        case .missingEntry:
            return "This dictionary entry was not found."
        case .loadFailed:
            return "The dictionary file could not be loaded. Repair the file and reload it before making changes."
        }
    }
}

public final class DictionaryStore: ObservableObject {
    @Published public private(set) var entries: [DictionaryEntry]
    @Published public private(set) var loadError: String?

    public let fileURL: URL
    private let defaultEntries: [DictionaryEntry]

    public init(
        fileURL: URL,
        defaultEntries: [DictionaryEntry] = DictionaryEntry.defaultEntries
    ) {
        self.fileURL = fileURL
        self.defaultEntries = defaultEntries
        let loaded = Self.loadEntries(fileURL: fileURL, defaultEntries: defaultEntries)
        self.entries = loaded.entries
        self.loadError = loaded.error
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
        try ensureLoaded()
        let entry = try makeDictionaryEntry(id: UUID(), phrase: phrase, aliasesText: aliasesText)
        try validate(entry, excluding: nil)
        try save(entries + [entry])
    }

    public func updateEntry(id: UUID, phrase: String, aliasesText: String) throws {
        try ensureLoaded()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw DictionaryStoreError.missingEntry
        }
        let entry = try makeDictionaryEntry(id: id, phrase: phrase, aliasesText: aliasesText)
        try validate(entry, excluding: id)
        var updatedEntries = entries
        updatedEntries[index] = entry
        try save(updatedEntries)
    }

    public func deleteEntry(id: UUID) throws {
        try ensureLoaded()
        guard entries.contains(where: { $0.id == id }) else {
            throw DictionaryStoreError.missingEntry
        }
        try save(entries.filter { $0.id != id })
    }

    public func reload() {
        let loaded = Self.loadEntries(fileURL: fileURL, defaultEntries: defaultEntries)
        if let error = loaded.error {
            loadError = error
            return
        }
        entries = loaded.entries
        loadError = nil
    }

    private func ensureLoaded() throws {
        guard loadError == nil else { throw DictionaryStoreError.loadFailed }
    }

    private func validate(_ entry: DictionaryEntry, excluding id: UUID?) throws {
        for existingEntry in entries where existingEntry.id != id {
            if dictionaryKey(existingEntry.phrase) == dictionaryKey(entry.phrase) {
                throw DictionaryStoreError.duplicatePhrase(entry.phrase)
            }
            let existingAliases = Set(existingEntry.aliases.map(dictionaryKey))
            if let alias = entry.aliases.first(where: { existingAliases.contains(dictionaryKey($0)) }) {
                throw DictionaryStoreError.conflictingAlias(alias)
            }
        }
    }

    private func save(_ candidateEntries: [DictionaryEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(candidateEntries)
        try data.write(to: fileURL, options: .atomic)
        entries = candidateEntries
    }

    private static func loadEntries(
        fileURL: URL,
        defaultEntries: [DictionaryEntry]
    ) -> (entries: [DictionaryEntry], error: String?) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let readError = error as NSError
            if readError.domain == NSCocoaErrorDomain && readError.code == NSFileReadNoSuchFileError {
                return (defaultEntries, nil)
            }
            return (defaultEntries, "Could not read the dictionary file: \(error.localizedDescription)")
        }
        do {
            return (try JSONDecoder().decode([DictionaryEntry].self, from: data), nil)
        } catch {
            return (defaultEntries, "The dictionary file is invalid: \(error.localizedDescription)")
        }
    }
}

private func makeDictionaryEntry(id: UUID, phrase: String, aliasesText: String) throws -> DictionaryEntry {
    let normalizedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPhrase.isEmpty else {
        throw DictionaryStoreError.emptyPhrase
    }
    let aliases = parseDictionaryAliases(aliasesText)
    guard !aliases.isEmpty else {
        throw DictionaryStoreError.emptyAliases
    }
    return DictionaryEntry(id: id, phrase: normalizedPhrase, aliases: aliases)
}

private func parseDictionaryAliases(_ aliasesText: String) -> [String] {
    var seenAliases: Set<String> = []
    return aliasesText
        .split(whereSeparator: { $0 == "," || $0 == "\n" })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { alias in
            guard !alias.isEmpty else { return false }
            return seenAliases.insert(dictionaryKey(alias)).inserted
        }
}

private func dictionaryKey(_ phrase: String) -> String {
    phrase.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
}
