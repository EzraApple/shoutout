import Foundation

public struct TextInsertionFormattingOptions: Equatable, Sendable {
    public var appendTrailingSpace: Bool
    public var useSmartSpacing: Bool

    public init(
        appendTrailingSpace: Bool = true,
        useSmartSpacing: Bool = true
    ) {
        self.appendTrailingSpace = appendTrailingSpace
        self.useSmartSpacing = useSmartSpacing
    }

    public static let `default` = TextInsertionFormattingOptions()
}

public struct TextInsertionContext: Equatable, Sendable {
    public var characterBefore: Character?
    public var characterAfter: Character?

    public init(characterBefore: Character?, characterAfter: Character?) {
        self.characterBefore = characterBefore
        self.characterAfter = characterAfter
    }

    public init?(text: String, selectedUTF16Range: NSRange) {
        guard selectedUTF16Range.location >= 0, selectedUTF16Range.length >= 0 else {
            return nil
        }

        let utf16 = text.utf16
        guard
            let start16 = utf16.index(
                utf16.startIndex,
                offsetBy: selectedUTF16Range.location,
                limitedBy: utf16.endIndex
            ),
            let end16 = utf16.index(
                start16,
                offsetBy: selectedUTF16Range.length,
                limitedBy: utf16.endIndex
            ),
            let start = String.Index(start16, within: text),
            let end = String.Index(end16, within: text)
        else {
            return nil
        }

        characterBefore = start > text.startIndex ? text[text.index(before: start)] : nil
        characterAfter = end < text.endIndex ? text[end] : nil
    }
}

public struct TextInsertionFormattingResult: Equatable, Sendable {
    public var text: String
    public var strategy: String
}

public enum TextInsertionFormatter {
    public static func prepare(
        _ text: String,
        context: TextInsertionContext?,
        options: TextInsertionFormattingOptions = .default
    ) -> TextInsertionFormattingResult {
        guard options.appendTrailingSpace else {
            return TextInsertionFormattingResult(text: text, strategy: "exact")
        }

        if options.useSmartSpacing, let context {
            let prefix = shouldPrefixSpace(before: context.characterBefore, text: text) ? " " : ""
            let suffix = shouldSuffixSpace(after: context.characterAfter, text: text) ? " " : ""
            return TextInsertionFormattingResult(
                text: prefix + text + suffix,
                strategy: "smart"
            )
        }

        return TextInsertionFormattingResult(
            text: fallbackTrailingSpace(for: text),
            strategy: options.useSmartSpacing ? "fallbackTrailing" : "trailing"
        )
    }

    private static func fallbackTrailingSpace(for text: String) -> String {
        guard let last = text.last, !last.isInsertionWhitespace else {
            return text
        }

        return text + " "
    }

    private static func shouldPrefixSpace(before: Character?, text: String) -> Bool {
        guard let before, !before.isInsertionWhitespace else { return false }
        guard let first = text.first, !first.isInsertionWhitespace else { return false }
        guard !Self.leadingPunctuation.contains(first) else { return false }
        guard !Self.openingPunctuation.contains(before) else { return false }
        return true
    }

    private static func shouldSuffixSpace(after: Character?, text: String) -> Bool {
        guard let after, !after.isInsertionWhitespace else { return false }
        guard let last = text.last, !last.isInsertionWhitespace else { return false }
        guard !Self.closingPunctuation.contains(after) else { return false }
        guard !Self.openingPunctuation.contains(last) else { return false }
        return true
    }

    private static let leadingPunctuation: Set<Character> = [
        ".", ",", "?", "!", ":", ";", ")", "]", "}", "%",
    ]

    private static let closingPunctuation: Set<Character> = [
        ".", ",", "?", "!", ":", ";", ")", "]", "}", "%",
    ]

    private static let openingPunctuation: Set<Character> = [
        "(", "[", "{", "$", "#", "@",
    ]
}

private extension Character {
    var isInsertionWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
