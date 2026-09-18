import Foundation

public enum LanguagePassOutputFormatter {
    /// Formats only the selected safe output; rejected model text is never reused.
    public static func format(
        source: String, finalText: String, style: LanguagePassStyle,
        enabled: Bool, fallbackReason: String?
    ) -> (text: String, numericFallback: Bool) {
        guard enabled, fallbackReason != "disabled", fallbackReason != "empty_input" else {
            return (finalText, false)
        }
        switch style {
        case .standard, .formal:
            return (sentenceCase(finalText), false)
        case .casual:
            if fallbackReason != nil { return (casualFallback(source), false) }
            if !preservesNumbers(source: source, candidate: finalText) {
                return (casualFallback(source), true)
            }
            return (finalText, false)
        }
    }

    private static let numericPattern = #"(?<![\p{L}\p{N}_])[+-]?\d+(?:[.,:/-](?:\d+|[xX]))*%?(?![\p{L}\p{N}_])"#
    private static let protectedPattern = #"`[^`]*`|https?://[^\s]+|[\w.%+-]+@[\w.-]+|(?:[\w.-]+/)+[\w./-]+|\b\w+_\w+\b|\b[a-z]+[A-Z][A-Za-z0-9]*\b|\b(?:e\.g|i\.e|[A-Z](?:\.[A-Z])+)\.|\b[\w-]+(?:\.[\w-]+)+\b|\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc)\."#

    public static func numericTokens(_ text: String) -> [String] {
        matches(numericPattern, in: text).map { String(text[Range($0.range, in: text)!]).lowercased() }
    }

    public static func preservesNumbers(source: String, candidate: String) -> Bool {
        var available = numericTokens(candidate)
        for number in numericTokens(source) {
            guard let index = available.firstIndex(of: number) else { return false }
            available.remove(at: index)
        }
        return true
    }

    public static func casualFallback(_ source: String) -> String {
        let protected = mask(source, pattern: numericPattern)
        let styled = LanguagePassMechanicalNormalizer.normalize(protected.text, style: .casual)
        return protected.restore(styled, lowercase: true)
    }

    public static func sentenceCase(_ source: String) -> String {
        // Fenced/inline code, shell commands, assignments, and standalone paths
        // are not prose. Preserve these lines rather than guess their syntax.
        var inFence = false
        return source.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                return line
            }
            if inFence || isTechnicalLine(line) { return line }
            let protected = mask(line, pattern: protectedPattern + "|" + numericPattern)
            // Ambiguous single-letter identifiers must not become the pronoun I.
            var result = replace(#"\bi(?=['’](?:m|d|ll|ve)\b|\s+(?:(?:just|also|still|really|probably|already|never)\s+)?(?:am|was|have|had|will|would|can|could|should|must|may|might|do|did|don't|didn't|want|need|think|know|like|mean|wonder|agree|hope|believe|feel|guess|remember)\b)"#, in: protected.text) { _ in "I" }
            result = replace(#"(^|[.!?]\s+)([\s\"“(']*)([a-z][\p{L}\p{N}_]*)"#, in: result) { match in
                let prefix = String(result[Range(match.range(at: 1), in: result)!])
                let quotes = String(result[Range(match.range(at: 2), in: result)!])
                let word = String(result[Range(match.range(at: 3), in: result)!])
                guard word != "i", word == word.lowercased(), let first = word.first else { return prefix + quotes + word }
                return prefix + quotes + String(first).uppercased() + word.dropFirst()
            }
            return protected.restore(result)
        }.joined(separator: "\n")
    }

    private static func isTechnicalLine(_ text: String) -> Bool {
        !matches(#"^\s*(?:[$>#]|(?:git|npm|pnpm|yarn|swift|python3?|curl|cd|export|echo|ls|cat|rg|grep|sed|awk|bash|zsh|sh|node|npx|make|brew|pip3?)\s)|(?:\w+\s*(?:=|:=|=>)|\w+\([^)]*\)|[{}])"#, in: text).isEmpty
    }

    private struct ProtectedText {
        let text: String
        let replacements: [(String, String)]

        func restore(_ value: String, lowercase: Bool = false) -> String {
            replacements.reduce(value) { result, item in
                result.replacingOccurrences(of: item.0, with: lowercase ? item.1.lowercased() : item.1)
            }
        }
    }

    private static func mask(_ text: String, pattern: String) -> ProtectedText {
        var prefix = "\u{E000}"
        while text.contains(prefix) { prefix += "\u{E000}" }
        var replacements: [(String, String)] = []
        let result = replace(pattern, in: text) { match in
            let token = prefix + String(replacements.count) + "\u{E001}"
            replacements.append((token, String(text[Range(match.range, in: text)!])))
            return token
        }
        return ProtectedText(text: result, replacements: replacements)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func replace(_ pattern: String, in text: String, using replacement: (NSTextCheckingResult) -> String) -> String {
        var result = text
        for match in matches(pattern, in: text).reversed() {
            result.replaceSubrange(Range(match.range, in: result)!, with: replacement(match))
        }
        return result
    }
}
