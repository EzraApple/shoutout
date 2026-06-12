import Foundation

public struct DictionaryEntry: Codable, Identifiable, Sendable {
    public var id: UUID
    public var phrase: String
    public var aliases: [String]

    public init(id: UUID = UUID(), phrase: String, aliases: [String]) {
        self.id = id
        self.phrase = phrase
        self.aliases = aliases
    }

    public static let defaultEntries: [DictionaryEntry] = [
        DictionaryEntry(phrase: "Replo", aliases: ["rep low", "reply low"]),
        DictionaryEntry(phrase: "Linear", aliases: ["line ear"]),
    ]
}

extension DictionaryEntry: Equatable {
    public static func == (left: DictionaryEntry, right: DictionaryEntry) -> Bool {
        left.phrase == right.phrase && left.aliases == right.aliases
    }
}
