import Foundation

public enum LanguagePassMechanicalNormalizer {
    public static func normalize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            return ""
        }

        result = removeAbandonedArticlesBeforeActually(from: result)
        result = removeStandaloneFillers(from: result)
        result = collapseRepeatedStarts(in: result)
        result = normalizeSpacing(in: result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeAbandonedArticlesBeforeActually(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\b(?:a|an)\s*(?:\.\.\.|…)\s+(actually\b)"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func removeStandaloneFillers(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(^|[ \t,]+)\b(?:um|uh|er)\b(?=$|[ \t,.;:!?])[, \t]*"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func collapseRepeatedStarts(in text: String) -> String {
        var result = text
        for pattern in repeatedStartPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    private static func normalizeSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" +([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #",\s*([.!?;:])"#, with: "$1", options: .regularExpression)
    }

    private static let repeatedStartPatterns = [
        #"^\s*(i)\s+\1\b"#,
        #"^\s*(we)\s+\1\b"#,
        #"^\s*(you)\s+\1\b"#,
        #"^\s*(yeah)\s+\1\b"#,
        #"^\s*(please)\s+\1\b"#,
        #"^\s*(can you)\s+\1\b"#,
        #"^\s*(could you)\s+\1\b"#,
        #"^\s*(would you)\s+\1\b"#,
        #"^\s*(can we)\s+\1\b"#,
        #"^\s*(could we)\s+\1\b"#,
        #"^\s*(would we)\s+\1\b"#,
    ]
}
