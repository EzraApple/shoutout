import Foundation

public struct LanguagePassExample: Equatable, Sendable {
    public var input: String
    public var output: String

    public init(input: String, output: String) {
        self.input = input
        self.output = output
    }
}

public struct LanguagePassValidation: Equatable, Sendable {
    public var acceptedText: String?
    public var fallbackReason: String?

    public var isAccepted: Bool {
        acceptedText != nil
    }

    public init(acceptedText: String?, fallbackReason: String?) {
        self.acceptedText = acceptedText
        self.fallbackReason = fallbackReason
    }
}

public enum LanguagePassStyle: String, CaseIterable, Identifiable, Sendable {
    case standard
    case casual
    case formal

    public static let defaultStyle: LanguagePassStyle = .standard

    public var id: String { rawValue }

    public init(storedValue: String?) {
        self = storedValue.flatMap(LanguagePassStyle.init(rawValue:)) ?? .defaultStyle
    }

    public var title: String {
        switch self {
        case .standard:
            return "Normal"
        case .casual:
            return "Casual"
        case .formal:
            return "Formal"
        }
    }

    public var detail: String {
        switch self {
        case .standard:
            return "Balanced punctuation and sentence casing."
        case .casual:
            return "Lowercase text with almost no added punctuation."
        case .formal:
            return "Clear sentence casing and punctuation for polished text."
        }
    }

    fileprivate var formattingInstruction: String {
        switch self {
        case .standard:
            return "Add light punctuation and sentence casing when obvious."
        case .casual:
            return "Use lowercase and almost no punctuation. Remove ordinary sentence-ending periods, question marks, and exclamation points even when they appear in the input."
        case .formal:
            return "Add clear sentence casing and punctuation when obvious."
        }
    }

    fileprivate var instruction: String {
        switch self {
        case .standard:
            return "Use a normal style: sentence casing, natural punctuation, and no extra polish."
        case .casual:
            return "Use a casual style: keep casual wording, avoid corporate polish, and stay close to the raw transcript."
        case .formal:
            return "Use a formal style: use clear sentence casing and punctuation, but do not change the speaker's word choice."
        }
    }

}

public enum LanguagePassPrompt {
    public static var systemInstructions: String {
        systemInstructions(for: .defaultStyle)
    }

    public static func systemInstructions(for style: LanguagePassStyle) -> String {
        """
        You are a dictation cleanup filter.
        The user message contains the transcript to clean.
        Return only the final text to paste.
        Do not include labels, quotes, markdown, or explanation.
        This is not a chat. Rewrite the dictated words; do not answer the speaker.
        Preserve the speaker's meaning, perspective, and task details. Do not summarize. Do not add facts.
        Clean obvious speech artifacts: filler words, repeated starts, stutters, and self-corrections.
        Remove abandoned articles before corrections, such as "a... actually" or "an... actually"; keep "actually".
        Remove filler words like "um", "uh", "er", and "you know"; do not preserve them as punctuated words.
        Keep the final choice when the speaker corrects themself.
        Do not remove casual wording like "wait, no, actually" when it is the sentence the speaker meant to say.
        \(style.formattingInstruction)
        \(style.instruction)
        Return the same text only if it is already clean and already matches the selected style.
        """
    }

    public static var examples: [LanguagePassExample] {
        examples(for: .defaultStyle)
    }

    public static func examples(for style: LanguagePassStyle) -> [LanguagePassExample] {
        switch style {
        case .casual:
            return style.examples
        case .standard, .formal:
            return baseExamples + style.examples
        }
    }

    private static let baseExamples: [LanguagePassExample] = [
        LanguagePassExample(
            input: "um can you can you send this over when you get a chance",
            output: "Can you send this over when you get a chance?"
        ),
        LanguagePassExample(
            input: "i think this works but maybe we should test it first",
            output: "I think this works, but maybe we should test it first."
        ),
        LanguagePassExample(
            input: "can you review this when you have time",
            output: "Can you review this when you have time?"
        ),
        LanguagePassExample(
            input: "wait no actually make it the smaller one",
            output: "Wait, no, actually make it the smaller one."
        ),
        LanguagePassExample(
            input: "i i think we should ship the smaller version",
            output: "I think we should ship the smaller version."
        ),
        LanguagePassExample(
            input: "i want to meet on tuesday wait no monday",
            output: "I want to meet on Monday."
        ),
        LanguagePassExample(
            input: "set the meeting for tuesday er monday",
            output: "Set the meeting for Monday."
        ),
        LanguagePassExample(
            input: "send it to alex uh no send it to sam",
            output: "Send it to Sam."
        ),
        LanguagePassExample(
            input: "make it red wait no make it blue",
            output: "Make it blue."
        ),
        LanguagePassExample(
            input: "book it for friday no sorry thursday",
            output: "Book it for Thursday."
        ),
        LanguagePassExample(
            input: "open the settings panel and turn on the beta option",
            output: "Open the settings panel and turn on the beta option."
        ),
        LanguagePassExample(
            input: "this is fine leave it exactly how it is",
            output: "This is fine. Leave it exactly how it is."
        ),
        LanguagePassExample(
            input: "the first version was better but the second one had better colors",
            output: "The first version was better, but the second one had better colors."
        ),
        LanguagePassExample(
            input: "Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?",
            output: "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?"
        ),
    ]

    fileprivate static let casualExamples: [LanguagePassExample] = [
        LanguagePassExample(
            input: "um yeah yeah that works can you send it over",
            output: "yeah that works can you send it over"
        ),
        LanguagePassExample(
            input: "wait no actually make it the smaller one",
            output: "wait no actually make it the smaller one"
        ),
        LanguagePassExample(
            input: "Can you send this over when you get a chance?",
            output: "can you send this over when you get a chance"
        ),
    ]

    fileprivate static let formalExamples: [LanguagePassExample] = [
        LanguagePassExample(
            input: "i can join monday probably around three",
            output: "I can join Monday, probably around three."
        ),
        LanguagePassExample(
            input: "can you review this when you have time",
            output: "Can you review this when you have time?"
        ),
    ]

    fileprivate static let standardExamples: [LanguagePassExample] = []

    public static func userPrompt(for input: String, style: LanguagePassStyle = .defaultStyle) -> String {
        switch style {
        case .casual:
            return """
            Casual cleanup required. Copying polished capitalization or ending punctuation is invalid.
            Transcript: \(input)
            Casual output:
            """
        case .standard:
            return """
            Rewrite this dictation transcript.
            Rules:
            - remove filler words, accidental repeats, and false starts
            - if the transcript says "a... actually" or "an... actually", delete the abandoned article and keep "actually"
            - return only the cleaned text
            Transcript:
            \(input)
            Cleaned:
            """
        case .formal:
            return """
            Rewrite this dictation transcript in formal style.
            Rules:
            - add clear sentence casing and punctuation when obvious
            - keep the speaker's original words
            - return only the cleaned text
            Transcript:
            \(input)
            Cleaned:
            """
        }
    }
}

private extension LanguagePassStyle {
    var examples: [LanguagePassExample] {
        switch self {
        case .standard:
            return LanguagePassPrompt.standardExamples
        case .casual:
            return LanguagePassPrompt.casualExamples
        case .formal:
            return LanguagePassPrompt.formalExamples
        }
    }
}

public enum LanguagePassValidator {
    public static func validate(output: String, baseText: String) -> LanguagePassValidation {
        validate(candidate: extractCandidate(from: output), baseText: baseText)
    }

    public static func extractCandidate(from output: String) -> String {
        var candidate = trim(output)

        let leadingLabels = [
            "Output:",
            "Final:",
            "Cleaned:",
            "Cleaned text:",
            "Rewrite:",
            "Rewritten:",
            "Text:",
        ]

        var strippedLabel = true
        while strippedLabel {
            strippedLabel = false
            for label in leadingLabels {
                if candidate.range(of: label, options: [.caseInsensitive, .anchored]) != nil {
                    candidate = trim(String(candidate.dropFirst(label.count)))
                    strippedLabel = true
                }
            }
        }

        if candidate.count >= 2,
            let first = candidate.first,
            let last = candidate.last,
            ((first == "\"" && last == "\"") || (first == "'" && last == "'")),
            !candidate.dropFirst().dropLast().contains("\n")
        {
            candidate = trim(String(candidate.dropFirst().dropLast()))
        }

        return candidate
    }

    public static func validate(candidate rawCandidate: String, baseText: String) -> LanguagePassValidation {
        let base = trim(baseText)
        let normalizedBase = normalize(base)
        guard !base.isEmpty else {
            return .init(acceptedText: nil, fallbackReason: "empty_input")
        }

        let candidate = extractCandidate(from: rawCandidate)
        let normalizedCandidate = normalize(candidate)
        guard !candidate.isEmpty else {
            return .init(acceptedText: nil, fallbackReason: "empty_output")
        }

        guard !looksLikeAssistantChatter(candidate) else {
            return .init(acceptedText: nil, fallbackReason: "assistant_chatter")
        }

        guard hasSafeLengthRatio(candidate: normalizedCandidate, base: normalizedBase) else {
            return .init(acceptedText: nil, fallbackReason: "unsafe_length_ratio")
        }

        guard !introducesSuspiciousStructure(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "suspicious_structure")
        }

        guard !hasUnresolvedCorrectionMarker(candidate) else {
            return .init(acceptedText: nil, fallbackReason: "unresolved_correction")
        }

        guard !keepsReplacedSideOfCorrection(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "unresolved_correction")
        }

        guard !introducesPerspectiveShift(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "perspective_shift")
        }

        guard !leaksPromptFormat(candidate) else {
            return .init(acceptedText: nil, fallbackReason: "format_leak")
        }

        guard !introducesNewNumbers(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "new_numbers")
        }

        guard hasEnoughSourceOverlap(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "low_source_overlap")
        }

        guard doesNotAddMeaningfulWords(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "new_content")
        }

        guard retainsEnoughSourceContent(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "dropped_content")
        }

        if normalizedCandidate == normalizedBase {
            return .init(acceptedText: nil, fallbackReason: "unchanged")
        }

        return .init(acceptedText: candidate, fallbackReason: nil)
    }

    private static func normalize(_ text: String) -> String {
        trim(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasSafeLengthRatio(candidate: String, base: String) -> Bool {
        guard base.count >= 18 else {
            return candidate.count <= max(80, base.count * 3)
        }

        let ratio = Double(candidate.count) / Double(max(base.count, 1))
        return ratio >= 0.25 && ratio <= 1.65
    }

    private static func looksLikeAssistantChatter(_ text: String) -> Bool {
        let lower = text.lowercased()
        let rejectedPrefixes = [
            "sure,",
            "sure thing",
            "here is",
            "here's",
            "as an ai",
            "i can help",
            "i cleaned",
            "cleaned version",
            "the cleaned",
            "the final",
        ]
        return rejectedPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func introducesSuspiciousStructure(candidate: String, base: String) -> Bool {
        if candidate.contains("```"), !base.contains("```") {
            return true
        }
        if candidate.contains("http://") || candidate.contains("https://") {
            return !(base.contains("http://") || base.contains("https://"))
        }
        return false
    }

    private static func hasUnresolvedCorrectionMarker(_ text: String) -> Bool {
        let tokens = wordTokens(text)
        for index in tokens.indices {
            if unresolvedSingleMarkers.contains(tokens[index]),
                nearestMeaningfulToken(in: tokens, before: index) != nil
            {
                return true
            }
        }
        guard tokens.count >= 2 else {
            return false
        }
        for index in 0 ..< (tokens.count - 1) {
            if correctionMarkerPairs.contains([tokens[index], tokens[index + 1]]),
                nearestMeaningfulToken(in: tokens, before: index) != nil
            {
                return true
            }
        }
        return false
    }

    private static func keepsReplacedSideOfCorrection(candidate: String, base: String) -> Bool {
        let baseTokens = wordTokens(base)
        let candidateTokens = Set(meaningfulTokens(candidate))
        guard !baseTokens.isEmpty, !candidateTokens.isEmpty else {
            return false
        }

        for markerRange in correctionMarkerRanges(in: baseTokens) {
            guard let before = nearestMeaningfulToken(in: baseTokens, before: markerRange.lowerBound),
                let after = nearestMeaningfulToken(in: baseTokens, after: markerRange.upperBound),
                before != after
            else {
                continue
            }

            if candidateTokens.contains(before) {
                return true
            }
        }

        return false
    }

    private static func correctionMarkerRanges(in tokens: [String]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0

        while index < tokens.count {
            if index < tokens.count - 1,
                correctionMarkerPairs.contains([tokens[index], tokens[index + 1]])
            {
                ranges.append(index ..< index + 2)
                index += 2
                continue
            }

            if correctionMarkerSingles.contains(tokens[index]) {
                ranges.append(index ..< index + 1)
            }
            index += 1
        }

        return ranges
    }

    private static func nearestMeaningfulToken(in tokens: [String], before endIndex: Int) -> String? {
        guard endIndex > 0 else { return nil }

        for index in stride(from: endIndex - 1, through: 0, by: -1) {
            let token = tokens[index]
            if !stopTokens.contains(token), !removableTokens.contains(token) {
                return token
            }
        }

        return nil
    }

    private static func nearestMeaningfulToken(in tokens: [String], after startIndex: Int) -> String? {
        guard startIndex < tokens.count else { return nil }

        for index in startIndex ..< tokens.count {
            let token = tokens[index]
            if !stopTokens.contains(token), !removableTokens.contains(token) {
                return token
            }
        }

        return nil
    }

    private static let correctionMarkerPairs: Set<[String]> = [
        ["wait", "no"],
        ["no", "wait"],
        ["no", "sorry"],
        ["sorry", "no"],
        ["scratch", "that"],
        ["uh", "no"],
        ["um", "no"],
        ["er", "no"],
        ["i", "mean"],
    ]

    private static let correctionMarkerSingles: Set<String> = [
        "er", "uh", "um", "oops",
    ]

    private static let unresolvedSingleMarkers: Set<String> = [
        "er", "uh", "um", "oops",
    ]

    private static func introducesPerspectiveShift(candidate: String, base: String) -> Bool {
        let normalizedBase = " \(normalize(base).lowercased()) "
        let normalizedCandidate = " \(normalize(candidate).lowercased()) "

        if normalizedBase.contains(" can you "), normalizedCandidate.contains(" i can ") {
            return true
        }
        if wordTokens(base).contains("you"), !wordTokens(candidate).contains("you"),
            wordTokens(candidate).contains("i")
        {
            return true
        }
        return false
    }

    private static func leaksPromptFormat(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("input:") || lower.contains("output:")
    }

    private static func introducesNewNumbers(candidate: String, base: String) -> Bool {
        let baseNumbers = Set(numberTokens(base))
        let candidateNumbers = Set(numberTokens(candidate))
        return !candidateNumbers.subtracting(baseNumbers).isEmpty
    }

    private static func hasEnoughSourceOverlap(candidate: String, base: String) -> Bool {
        let baseTokens = Set(meaningfulTokens(base))
        let candidateTokens = meaningfulTokens(candidate)
        guard !candidateTokens.isEmpty else {
            return true
        }
        guard !baseTokens.isEmpty else {
            return candidateTokens.count <= 2
        }

        let sourcedCount = candidateTokens.filter { baseTokens.contains($0) }.count
        let ratio = Double(sourcedCount) / Double(candidateTokens.count)
        return ratio >= 0.72
    }

    private static func doesNotAddMeaningfulWords(candidate: String, base: String) -> Bool {
        let baseTokens = Set(meaningfulTokens(base))
        let additions = meaningfulTokens(candidate).filter { token in
            !baseTokens.contains(token) && !safeAddedTokens.contains(token)
        }
        return Set(additions).count <= 1
    }

    private static func retainsEnoughSourceContent(candidate: String, base: String) -> Bool {
        let baseTokens = meaningfulTokens(base).filter { !removableTokens.contains($0) }
        guard baseTokens.count >= 4 else {
            return true
        }

        let candidateTokens = Set(meaningfulTokens(candidate))
        let retainedCount = baseTokens.filter { candidateTokens.contains($0) }.count
        let ratio = Double(retainedCount) / Double(baseTokens.count)
        return ratio >= 0.60
    }

    private static func numberTokens(_ text: String) -> [String] {
        wordTokens(text).filter { $0.allSatisfy(\.isNumber) }
    }

    private static func meaningfulTokens(_ text: String) -> [String] {
        wordTokens(text).filter { !stopTokens.contains($0) }
    }

    private static func wordTokens(_ text: String) -> [String] {
        text.lowercased().split { character in
            !(character.isLetter || character.isNumber || character == "'")
        }.map(String.init)
    }

    private static let stopTokens: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "could",
        "did", "do", "does", "for", "from", "had", "has", "have", "he", "her",
        "him", "his", "i", "if", "in", "is", "it", "its", "me", "my", "of",
        "on", "or", "our", "she", "so", "that", "the", "their", "them", "then",
        "there", "these", "they", "this", "those", "to", "was", "we", "were",
        "when", "with", "would", "you", "your",
    ]

    private static let safeAddedTokens: Set<String> = stopTokens.union([
        "actually", "maybe", "please",
    ])

    private static let removableTokens: Set<String> = [
        "um", "uh", "er", "oops", "wait", "no", "sorry", "scratch", "actually", "maybe",
    ]
}
