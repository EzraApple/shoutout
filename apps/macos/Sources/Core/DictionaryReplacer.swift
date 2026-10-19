import Foundation

public enum DictionaryReplacer {
    public static func replace(_ text: String, entries: [DictionaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var matches: [Match] = []
        var order = 0

        for entry in entries {
            for alias in entry.aliases {
                defer { order += 1 }
                guard !alias.isEmpty else { continue }
                let escapedAlias = NSRegularExpression.escapedPattern(for: alias)
                let wordCharacters = #"\p{L}\p{N}\p{M}\p{Pc}"#
                let pattern = "(?<![\(wordCharacters)])\(escapedAlias)(?![\(wordCharacters)])"
                guard let expression = try? NSRegularExpression(
                    pattern: pattern,
                    options: .caseInsensitive
                ) else { continue }
                for result in expression.matches(in: text, range: fullRange) {
                    matches.append(Match(
                        range: result.range,
                        aliasLength: alias.count,
                        order: order,
                        replacement: entry.phrase
                    ))
                }
            }
        }

        matches.sort {
            if $0.aliasLength != $1.aliasLength { return $0.aliasLength > $1.aliasLength }
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.order < $1.order
        }

        var selected: [Match] = []
        for match in matches {
            guard !selected.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 })
            else { continue }
            selected.append(match)
        }
        guard !selected.isEmpty else { return text }
        selected.sort { $0.range.location < $1.range.location }

        var output = ""
        var cursor = 0
        for match in selected {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += match.replacement
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }

    private struct Match {
        let range: NSRange
        let aliasLength: Int
        let order: Int
        let replacement: String
    }
}
