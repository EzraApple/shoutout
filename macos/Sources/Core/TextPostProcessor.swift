import Foundation

public struct TextPostProcessingOptions: Equatable, Sendable {
    public var removeFillerWords: Bool
    public var cleanUpSelfCorrections: Bool
    public var applySpokenCommands: Bool
    public var collapseWhitespace: Bool

    public init(
        removeFillerWords: Bool = true,
        cleanUpSelfCorrections: Bool = true,
        applySpokenCommands: Bool = true,
        collapseWhitespace: Bool = true
    ) {
        self.removeFillerWords = removeFillerWords
        self.cleanUpSelfCorrections = cleanUpSelfCorrections
        self.applySpokenCommands = applySpokenCommands
        self.collapseWhitespace = collapseWhitespace
    }

    public static let `default` = TextPostProcessingOptions()
}

public struct DictationResult: Equatable, Sendable {
    public var rawText: String
    public var finalText: String

    public init(rawText: String, finalText: String) {
        self.rawText = rawText
        self.finalText = finalText
    }
}

public enum TextPostProcessor {
    public static func process(
        _ text: String,
        options: TextPostProcessingOptions = .default,
        dictionaryEntries: [DictionaryEntry] = DictionaryEntry.defaultEntries
    ) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            return ""
        }

        if options.removeFillerWords {
            result = removeFillers(from: result)
        }

        if options.cleanUpSelfCorrections {
            result = cleanUpSelfCorrections(in: result)
        }

        if options.applySpokenCommands {
            result = applySpokenCommands(to: result)
        }

        result = applyDictionary(to: result, entries: dictionaryEntries)

        if options.collapseWhitespace {
            result = collapseWhitespace(in: result)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeFillers(from text: String) -> String {
        var result = text
        let patterns = [
            "\\b[Uu]m\\b,?\\s*",
            "\\b[Uu]h\\b,?\\s*",
            "\\b[Yy]ou know\\b,?\\s*",
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return result
    }

    private static func cleanUpSelfCorrections(in text: String) -> String {
        var result = text

        let repeatedActionPattern =
            #"\b(press|click|open|use|select|choose|set|make|call|send|go|do)\s+([^,.!?\n]+?)\s+(?:oh\s+)?(?:i mean|actually|scratch that|or rather|rather)\s+(?:or\s+)?\1\s+([^,.!?\n]+?)(?:\s+rather)?(?=$|[,.!?\n])"#
        result = result.replacingOccurrences(
            of: repeatedActionPattern,
            with: "$1 $3",
            options: [.regularExpression, .caseInsensitive]
        )

        let prepositionCorrectionPattern =
            #"\b(at|on|for|by|to|from|with)\s+([^,.!?\n]+?)\s+(?:actually|scratch that|or rather|rather|i mean)\s+([^,.!?\n]+?)(?=$|[,.!?\n])"#
        result = result.replacingOccurrences(
            of: prepositionCorrectionPattern,
            with: "$1 $3",
            options: [.regularExpression, .caseInsensitive]
        )

        let trailingCorrectionMarkerPattern = #"\s+(?:oh\s+)?(?:i mean|or rather|rather)\s*$"#
        result = result.replacingOccurrences(
            of: trailingCorrectionMarkerPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }

    private static func applySpokenCommands(to text: String) -> String {
        var result = text
        let replacements = [
            ("\\s+new paragraph\\b", "\n\n"),
            ("\\s+new line\\b", "\n"),
            ("\\s+question mark\\b", "?"),
            ("\\s+exclamation point\\b", "!"),
            ("\\s+exclamation mark\\b", "!"),
            ("\\s+period\\b", "."),
        ]

        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private static func applyDictionary(
        to text: String,
        entries: [DictionaryEntry]
    ) -> String {
        var result = text

        let replacementPairs = entries
            .flatMap { entry in
                entry.aliases.map { alias in (alias: alias, phrase: entry.phrase) }
            }
            .sorted { left, right in
                left.alias.count > right.alias.count
            }

        for pair in replacementPairs {
            guard !pair.alias.isEmpty else {
                continue
            }

            let escapedAlias = NSRegularExpression.escapedPattern(for: pair.alias)
            let pattern = "(?<![\\p{L}\\p{N}])\(escapedAlias)(?![\\p{L}\\p{N}])"
            result = result.replacingOccurrences(
                of: pattern,
                with: pair.phrase,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private static func collapseWhitespace(in text: String) -> String {
        var result = text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result
    }
}
