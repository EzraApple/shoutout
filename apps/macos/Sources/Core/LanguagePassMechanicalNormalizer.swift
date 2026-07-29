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

    public static func normalize(_ text: String, style: LanguagePassStyle) -> String {
        let normalized = normalize(text)
        switch style {
        case .casual:
            return applyCasualPlaintextStyle(to: normalized)
        case .standard, .formal:
            return normalized
        }
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

    private static func applyCasualPlaintextStyle(to text: String) -> String {
        text.lowercased()
            .replacingOccurrences(
                of: #"(\d+)\.0\b"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(\d+)\.x\b"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=\b[a-z])\.(?=[a-z]\b)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<=\b[a-z])\.(?=\s|$)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[-–—]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[,.!?;:"“”()\[\]{}]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
