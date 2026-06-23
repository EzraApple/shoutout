import Foundation

public enum LanguagePassDeterministicCleanup {
    public static func clean(
        _ text: String,
        style: LanguagePassStyle = .defaultStyle
    ) -> String {
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

        result = result.replacingOccurrences(
            of: #"\b(?:um|uh|er)\b,?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\b([\p{L}\p{N}]+(?:'[\p{L}\p{N}]+)?)\b(?:\s+\1\b)+"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )

        if style == .casual {
            result = result.lowercased()
            result = result.replacingOccurrences(
                of: #"[ \t]*[.!?]+$"#,
                with: "",
                options: .regularExpression
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
