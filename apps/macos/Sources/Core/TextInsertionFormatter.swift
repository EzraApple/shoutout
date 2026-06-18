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
    private static let contextWindowCharacterCount = 120

    public var characterBefore: Character?
    public var characterAfter: Character?
    public var textBefore: String
    public var textAfter: String
    public var selectedText: String
    public var hasTextWindow: Bool

    public init(
        characterBefore: Character?,
        characterAfter: Character?,
        textBefore: String? = nil,
        textAfter: String? = nil,
        selectedText: String = "",
        hasTextWindow: Bool = false
    ) {
        self.characterBefore = characterBefore
        self.characterAfter = characterAfter
        self.textBefore = textBefore ?? characterBefore.map(String.init) ?? ""
        self.textAfter = textAfter ?? characterAfter.map(String.init) ?? ""
        self.selectedText = selectedText
        self.hasTextWindow = hasTextWindow
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

        let before = String(text[..<start])
        let after = String(text[end...])
        let selected = String(text[start..<end])
        characterBefore = before.last
        characterAfter = after.first
        textBefore = String(before.suffix(Self.contextWindowCharacterCount))
        textAfter = String(after.prefix(Self.contextWindowCharacterCount))
        selectedText = selected
        hasTextWindow = true
    }
}

public struct TextInsertionTargetSnapshot: Equatable, Sendable {
    public var text: String
    public var selectedUTF16Range: NSRange
    public var placeholder: String?
    public var characterCount: Int?

    public init(
        text: String,
        selectedUTF16Range: NSRange,
        placeholder: String? = nil,
        characterCount: Int? = nil
    ) {
        self.text = text
        self.selectedUTF16Range = selectedUTF16Range
        self.placeholder = placeholder
        self.characterCount = characterCount
    }

    public var isPlaceholderValue: Bool {
        let normalizedText = Self.normalized(text)
        guard !normalizedText.isEmpty else {
            return false
        }

        if let characterCount {
            return characterCount == 0
        }

        if let placeholder,
            !placeholder.isEmpty,
            normalizedText == Self.normalized(placeholder)
        {
            return true
        }

        if Self.knownEmptyComposerPlaceholders.contains(normalizedText),
            selectedUTF16Range.location == 0,
            selectedUTF16Range.length == 0
        {
            return true
        }

        return false
    }

    public var editableText: String {
        isPlaceholderValue ? "" : text
    }

    public var editableSelectedUTF16Range: NSRange {
        isPlaceholderValue ? NSRange(location: 0, length: 0) : selectedUTF16Range
    }

    public var context: TextInsertionContext? {
        TextInsertionContext(text: editableText, selectedUTF16Range: editableSelectedUTF16Range)
    }

    private static let knownEmptyComposerPlaceholders: Set<String> = [
        "Ask for follow-up changes",
    ]

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let fittedText = fitCapitalization(text, context: context)
            let prefix = shouldPrefixSpace(before: context.characterBefore, text: fittedText) ? " " : ""
            let suffix = shouldSuffixSpace(after: context.characterAfter, text: fittedText) ? " " : ""
            return TextInsertionFormattingResult(
                text: prefix + fittedText + suffix,
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

    private static func fitCapitalization(_ text: String, context: TextInsertionContext) -> String {
        guard let firstLetterIndex = text.firstIndex(where: { $0.isInsertionLetter }) else {
            return text
        }
        guard context.hasTextWindow else {
            return text
        }
        guard text[..<firstLetterIndex].allSatisfy({ $0.isInsertionWhitespace || openingPunctuation.contains($0) || $0 == "\"" || $0 == "'" }) else {
            return text
        }
        guard isLikelyNaturalText(text), isLikelyNaturalContext(context) else {
            return text
        }

        let firstWord = firstWord(in: text, from: firstLetterIndex)
        if shouldLowercaseFirstWord(firstWord, context: context) {
            return replacingCharacter(at: firstLetterIndex, in: text) { Character(String($0).lowercased()) }
        }

        if shouldUppercaseFirstWord(firstWord, context: context) {
            return replacingCharacter(at: firstLetterIndex, in: text) { Character(String($0).uppercased()) }
        }

        return text
    }

    private static func shouldLowercaseFirstWord(
        _ firstWord: String,
        context: TextInsertionContext
    ) -> Bool {
        guard let previous = lastNonWhitespace(in: context.textBefore) else {
            return false
        }
        guard !trailingWhitespaceContainsNewline(context.textBefore) else {
            return false
        }
        guard !sentenceTerminators.contains(previous) else {
            return false
        }
        guard let first = firstWord.first, first.isUppercase else {
            return false
        }
        let lowered = firstWord.lowercased()
        guard lowercasedMidSentenceWords.contains(lowered) else {
            return false
        }
        return true
    }

    private static func shouldUppercaseFirstWord(
        _ firstWord: String,
        context: TextInsertionContext
    ) -> Bool {
        guard let first = firstWord.first, first.isLowercase else {
            return false
        }
        guard lowercasedMidSentenceWords.contains(firstWord.lowercased()) else {
            return false
        }
        if trailingWhitespaceContainsNewline(context.textBefore) {
            return true
        }
        guard let previous = lastNonWhitespace(in: context.textBefore) else {
            return context.textBefore.isEmpty
        }
        return sentenceTerminators.contains(previous)
    }

    private static func isLikelyNaturalText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("://") || lowered.contains("www.") {
            return false
        }

        let codeMarkers: Set<Character> = ["`", "{", "}", "=", "<", ">"]
        return !text.contains { codeMarkers.contains($0) }
    }

    private static func isLikelyNaturalContext(_ context: TextInsertionContext) -> Bool {
        let surrounding = context.textBefore + context.textAfter
        let lowered = surrounding.lowercased()
        if lowered.contains("://") || lowered.contains("www.") {
            return false
        }

        let codeMarkers: Set<Character> = ["`", "{", "}", "=", "<", ">"]
        return !surrounding.contains { codeMarkers.contains($0) }
    }

    private static func firstWord(in text: String, from start: String.Index) -> String {
        var end = start
        while end < text.endIndex, text[end].isInsertionLetter {
            end = text.index(after: end)
        }
        return String(text[start..<end])
    }

    private static func replacingCharacter(
        at index: String.Index,
        in text: String,
        transform: (Character) -> Character
    ) -> String {
        var updated = text
        updated.replaceSubrange(index...index, with: String(transform(text[index])))
        return updated
    }

    private static func lastNonWhitespace(in text: String) -> Character? {
        text.reversed().first { !$0.isInsertionWhitespace }
    }

    private static func trailingWhitespaceContainsNewline(_ text: String) -> Bool {
        for character in text.reversed() {
            guard character.isInsertionWhitespace else {
                return false
            }
            if character == "\n" {
                return true
            }
        }
        return text.contains("\n")
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

    private static let sentenceTerminators: Set<Character> = [
        ".", "?", "!", "\n",
    ]

    private static let lowercasedMidSentenceWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "because", "but", "by", "can",
        "could", "did", "do", "does", "for", "from", "had", "has", "have", "he",
        "here", "if", "in", "is", "it", "its", "let", "make", "maybe", "of", "on",
        "or", "please", "should", "so", "that", "the", "then", "there", "these",
        "they", "this", "those", "to", "was", "we", "were", "which", "will",
        "with", "would", "you",
    ]
}

private extension Character {
    var isInsertionWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var isInsertionLetter: Bool {
        unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    var isUppercase: Bool {
        guard isInsertionLetter else { return false }
        let value = String(self)
        return value == value.uppercased() && value != value.lowercased()
    }

    var isLowercase: Bool {
        guard isInsertionLetter else { return false }
        let value = String(self)
        return value == value.lowercased() && value != value.uppercased()
    }
}
