import Foundation

public struct TextPostProcessingOptions: Equatable, Sendable {
    public var removeFillerWords: Bool
    public var applySpokenCommands: Bool
    public var collapseWhitespace: Bool

    public init(
        removeFillerWords: Bool = true,
        applySpokenCommands: Bool = true,
        collapseWhitespace: Bool = true
    ) {
        self.removeFillerWords = removeFillerWords
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
        options: TextPostProcessingOptions = .default
    ) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            return ""
        }

        if options.removeFillerWords {
            result = removeFillers(from: result)
        }

        if options.applySpokenCommands {
            result = applySpokenCommands(to: result)
        }

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
