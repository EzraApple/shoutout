import Foundation

public enum LanguagePassDeterministicCleanup {
    public static func clean(_ text: String) -> String {
        var result = text

        let replacements = [
            (#"\b(?:a|an)\s*(?:\.\.\.|…)\s+(actually\b)"#, "$1"),
        ]

        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
