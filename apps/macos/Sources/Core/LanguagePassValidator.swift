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
            return "Lowercase text with no added punctuation."
        case .formal:
            return "Clear sentence casing and punctuation for polished text."
        }
    }

    fileprivate var formattingInstruction: String {
        switch self {
        case .standard:
            return "Add light punctuation and sentence casing when obvious."
        case .casual:
            return "Use lowercase. Do not add punctuation or sentence capitalization. Remove ordinary sentence-ending periods, question marks, and exclamation points even when they appear in the input."
        case .formal:
            return "Add clear sentence casing and punctuation when obvious."
        }
    }

    fileprivate var instruction: String {
        switch self {
        case .standard:
            return "Use a normal style: sentence casing, natural punctuation, and no extra polish."
        case .casual:
            return "Use a casual plaintext style: keep the same words, do not abbreviate words, stay lowercase, remove punctuation, and remove only fillers or accidental repeats."
        case .formal:
            return "Use a formal style: use clear sentence casing and punctuation, but keep the speaker's meaningful word choice."
        }
    }

}

public enum LanguagePassPrompt {
    public static var systemInstructions: String {
        systemInstructions(for: .defaultStyle)
    }

    public static func systemInstructions(for style: LanguagePassStyle) -> String {
        """
        You are Llama, created by Meta. You are a helpful assistant.
        You are a dictation cleanup filter.
        Return only the cleaned transcript text. Do not include labels, quotes, markdown, bullets, or explanation.
        This is not a chat. Edit the speaker's dictated words; never answer the speaker.
        Use the current transcript as the only source. Do not output examples or rules.
        Preserve the speaker's meaning, perspective, and task details. Do not summarize, omit task details, or add facts.
        Preserve command and request mood. Do not turn instructions into offers, promises, or future-tense status statements.
        Keep every meaningful content word unless it is filler, an accidental repeat, or the abandoned side of a self-correction.
        Clean obvious speech artifacts: filler words, repeated starts, stutters, and self-corrections.
        Remove abandoned articles before corrections, such as "a... actually" or "an... actually"; keep "actually".
        Remove filler words like "um", "uh", "er", and "you know"; do not preserve them as punctuated words.
        Remove discourse fillers only when they do not carry meaning, such as unnecessary "like", "basically", "literally", "kind of", and "sort of".
        When "basically" or "literally" only adds emphasis, remove it.
        Preserve "like" when it is the main verb or a comparison word, not a filler.
        Keep the final choice when the speaker corrects themself.
        Do not remove casual wording like "wait, no, actually" when it is the sentence the speaker meant to say.
        \(style.unsafeRewriteExamples)
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

    public static func examples(for style: LanguagePassStyle, input: String) -> [LanguagePassExample] {
        let lower = input.lowercased()

        switch style {
        case .casual:
            if lower.contains("um yeah") {
                return examples(matching: [
                    "um yeah yeah that works can you send it over",
                ], in: casualExamples)
            }
            if lower.contains("like") {
                return examples(matching: [
                    "Can you send this over when you get a chance?",
                    "I think this is, like, ready to ship.",
                ], in: casualExamples)
            }
            if lower.contains("wait no actually") {
                return examples(matching: [
                    "wait no actually make it the smaller one",
                ], in: casualExamples)
            }
            return examples(matching: [
                "Can you send this over when you get a chance?",
            ], in: casualExamples)

        case .formal:
            if lower.contains("basically") || lower.contains("literally") {
                return examples(matching: [
                    "this is basically ready for review",
                    "this is basically literally ready for review",
                ], in: formalExamples)
            }
            return examples(matching: [
                "i can join monday probably around three",
            ], in: formalExamples)

        case .standard:
            if lower.contains("from my transcript") {
                return examples(matching: [
                    "find from my transcript many more examples where the language model took too aggressive of a pass and messed things up",
                    "drop the random comments please",
                    "can you make the hero smaller and keep the buttons where they are",
                ], in: baseExamples)
            }
            if lower.contains("synthetic") || lower.contains("agent facing") || lower.contains("agent-facing") {
                return examples(matching: [
                    "you shouldn't want to comment asking if we could replace synthetic with like agent facing text as like a name that's a db column right",
                    "okay but if i merge this in main i can just tell that agent to look at this to help fix this issue",
                    "find from my transcript many more examples where the language model took too aggressive of a pass and messed things up",
                ], in: baseExamples)
            }
            if lower.contains("make me") || lower.contains("sub-agent") || lower.contains("sub agents") {
                return examples(matching: [
                    "make me two pages one owl themed and one octopus themed have two sub agents do it",
                    "please have a sub agent do the localhost thing",
                    "drop the random comments please",
                    "have the agent check the logs then summarize the errors",
                    "can you make the hero smaller and keep the buttons where they are",
                ], in: baseExamples)
            }
            if lower.contains("a... actually") || lower.contains("an... actually") {
                return examples(matching: [
                    "Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?",
                ], in: baseExamples)
            }
            if lower.contains("wait no actually") {
                return examples(matching: [
                    "i think this works but maybe we should test it first",
                    "wait no actually make it the smaller one",
                ], in: baseExamples)
            }
            if lower.contains(" er ") {
                return examples(matching: [
                    "i want to meet on tuesday er monday",
                ], in: baseExamples)
            }
            if lower.contains("wait no") {
                return examples(matching: [
                    "i want to meet on tuesday wait no monday",
                ], in: baseExamples)
            }
            if lower.contains(" like ") {
                let exampleInput = lower.hasPrefix("i like ") ? "i like this direction" : "i think this is like ready to ship"
                return examples(matching: [exampleInput], in: baseExamples)
            }
            if lower.contains("um") || lower.contains("can you can you") {
                return examples(matching: [
                    "um can you can you send this over when you get a chance",
                ], in: baseExamples)
            }
            if lower.contains("open the settings panel") {
                return examples(matching: [
                    "i think this works but maybe we should test it first",
                    "open the settings panel and turn on the beta option",
                ], in: baseExamples)
            }
            return examples(matching: [
                "i think this works but maybe we should test it first",
            ], in: baseExamples)
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
            input: "you shouldn't want to comment asking if we could replace synthetic with like agent facing text as like a name that's a db column right",
            output: "You shouldn't want to comment asking if we could replace synthetic with agent-facing text as a name. That's a DB column, right?"
        ),
        LanguagePassExample(
            input: "okay but if i merge this in main i can just tell that agent to look at this to help fix this issue",
            output: "Okay, but if I merge this in main, I can just tell that agent to look at this to help fix this issue."
        ),
        LanguagePassExample(
            input: "find from my transcript many more examples where the language model took too aggressive of a pass and messed things up",
            output: "Find from my transcript many more examples where the language model took too aggressive of a pass and messed things up."
        ),
        LanguagePassExample(
            input: "make me two pages one owl themed and one octopus themed have two sub agents do it",
            output: "Make me two pages, one owl-themed and one octopus-themed. Have two sub-agents do it."
        ),
        LanguagePassExample(
            input: "please have a sub agent do the localhost thing",
            output: "Please have a sub-agent do the localhost thing."
        ),
        LanguagePassExample(
            input: "drop the random comments please",
            output: "Drop the random comments, please."
        ),
        LanguagePassExample(
            input: "have the agent check the logs then summarize the errors",
            output: "Have the agent check the logs, then summarize the errors."
        ),
        LanguagePassExample(
            input: "can you make the hero smaller and keep the buttons where they are",
            output: "Can you make the hero smaller and keep the buttons where they are?"
        ),
        LanguagePassExample(
            input: "i think this is like ready to ship",
            output: "I think this is ready to ship."
        ),
        LanguagePassExample(
            input: "i like this direction",
            output: "I like this direction."
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
            input: "i want to meet on tuesday er monday",
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
            input: "Could you, like, review this when you have time?",
            output: "could you review this when you have time"
        ),
        LanguagePassExample(
            input: "wait no actually make it the smaller one",
            output: "wait no actually make it the smaller one"
        ),
        LanguagePassExample(
            input: "Can you send this over when you get a chance?",
            output: "can you send this over when you get a chance"
        ),
        LanguagePassExample(
            input: "I think this is, like, ready to ship.",
            output: "i think this is ready to ship"
        ),
        LanguagePassExample(
            input: "I like this direction.",
            output: "i like this direction"
        ),
    ]

    fileprivate static let formalExamples: [LanguagePassExample] = [
        LanguagePassExample(
            input: "i can join monday probably around three",
            output: "I can join Monday, probably around three."
        ),
        LanguagePassExample(
            input: "um can you like check the logs and tell me what's broken",
            output: "Can you check the logs and tell me what's broken?"
        ),
        LanguagePassExample(
            input: "can you review this when you have time",
            output: "Can you review this when you have time?"
        ),
        LanguagePassExample(
            input: "this is basically ready for review",
            output: "This is ready for review."
        ),
        LanguagePassExample(
            input: "this is basically literally ready for review",
            output: "This is ready for review."
        ),
    ]

    fileprivate static let standardExamples: [LanguagePassExample] = []

    public static func userPrompt(for input: String, style: LanguagePassStyle = .defaultStyle) -> String {
        switch style {
        case .casual:
            return """
            Rewrite as casual lowercase text.
            Keep the speaker's words. Do not abbreviate or substitute words.
            Do not output punctuation characters.
            Remove filler words such as um, uh, repeated words, and unnecessary like.
            Preserve meaningful like when it means enjoy or similar to.
            CURRENT TRANSCRIPT:
            \(input)
            FINAL TEXT:
            """
        case .standard:
            return """
            CURRENT TRANSCRIPT:
            \(input)
            FINAL TEXT:
            """
        case .formal:
            return """
            CURRENT TRANSCRIPT:
            \(input)
            FINAL TEXT (remove filler words such as basically and literally):
            """
        }
    }

    public static func retryPrompt(
        for input: String,
        style: LanguagePassStyle,
        previousOutput: String
    ) -> String? {
        let candidate = previousOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        switch style {
        case .standard, .formal:
            guard actuallyFalseStartNeedsRetry(input: input, output: candidate) else {
                return nil
            }

            return """
            Convert transcript to cleaned dictation output.
            Output only the converted text. Do not answer the transcript.
            When the transcript says "a... actually" or "an... actually", remove only the abandoned article and keep "actually".

            Input: Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?
            Output: Does this PR also make it actually register manage tabs and the suggestion tool with this thing?

            Input:
            \(input)
            Output:
            """
        case .casual:
            guard casualOutputNeedsRetry(candidate) else {
                return nil
            }

            return """
            Convert transcript to casual output.
            Output only the converted text. Do not answer the transcript.
            Keep the same words. Do not abbreviate or substitute words.

            Input: Can you send this over when you get a chance?
            Output: can you send this over when you get a chance

            Input: I think this is, like, ready to ship.
            Output: i think this is ready to ship

            Input:
            \(input)
            Output:
            """
        }
    }

    private static func examples(matching inputs: [String], in examples: [LanguagePassExample]) -> [LanguagePassExample] {
        inputs.compactMap { input in
            examples.first { $0.input == input }
        }
    }

    private static func casualOutputNeedsRetry(_ output: String) -> Bool {
        guard !output.isEmpty else { return false }

        if output != output.lowercased() {
            return true
        }
        if output.contains(where: { ".?!,".contains($0) }) {
            return true
        }

        let normalized = " \(output.lowercased()) "
        return normalized.contains(" is like ")
            || normalized.contains(" was like ")
            || normalized.contains(" are like ")
            || normalized.contains(" be like ")
    }

    private static func actuallyFalseStartNeedsRetry(input: String, output: String) -> Bool {
        let lowerInput = input.lowercased()
        guard lowerInput.contains("a... actually") || lowerInput.contains("an... actually") else {
            return false
        }

        let outputTokens = Set(output.lowercased().split { !$0.isLetter }.map(String.init))
        return !outputTokens.contains("actually")
    }
}

private extension LanguagePassStyle {
    var unsafeRewriteExamples: String {
        switch self {
        case .standard, .formal:
            return """
            Unsafe rewrite patterns:
            - Do not delete a leading subject phrase such as "the diff is" from a sentence.
            - Do not delete the request frame from a request, such as "can you".
            - Do not turn a command like "make me two pages" into "I can make two pages".
            - Do not turn an instruction like "have two sub-agents do it" into "two sub-agents will do it".
            - Do not delete "wait no actually" when those words are the intended command rather than a correction marker.
            """
        case .casual:
            return """
            Unsafe rewrite patterns:
            - Do not delete a leading subject phrase such as "the diff is" from a sentence.
            - Do not delete the request frame from a request, such as "can you".
            - Do not turn a command like "make me two pages" into "I can make two pages".
            - Do not turn an instruction like "have two sub-agents do it" into "two sub-agents will do it".
            - Do not delete "wait no actually" when those words are the intended command rather than a correction marker.
            """
        }
    }

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

        if let firstLine = candidate.split(whereSeparator: \.isNewline).first,
            candidate.contains("\n\n")
        {
            candidate = trim(String(firstLine))
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

        guard !dropsRequestRecipient(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "dropped_content")
        }

        guard !leaksPromptFormat(candidate) else {
            return .init(acceptedText: nil, fallbackReason: "format_leak")
        }

        guard !introducesNewNumbers(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "new_numbers")
        }

        guard !dropsMeaningfulLike(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "dropped_content")
        }

        guard retainsRequiredSourceTokens(candidate: candidate, base: base) else {
            return .init(acceptedText: nil, fallbackReason: "dropped_content")
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
        if introducesSuspiciousQuoteMarks(candidate: candidate, base: base) {
            return true
        }
        if containsMarkupTag(candidate), !containsMarkupTag(base) {
            return true
        }
        if candidate.contains("http://") || candidate.contains("https://") {
            return !(base.contains("http://") || base.contains("https://"))
        }
        return false
    }

    private static func introducesSuspiciousQuoteMarks(candidate: String, base: String) -> Bool {
        let quoteCharacters = CharacterSet(charactersIn: "\"“”")
        guard candidate.rangeOfCharacter(from: quoteCharacters) != nil,
            base.rangeOfCharacter(from: quoteCharacters) == nil
        else {
            return false
        }

        let baseTokens = Set(wordTokens(base))
        return quotedSpans(in: candidate).contains { span in
            let tokens = wordTokens(span)
            guard tokens.count == 1, let token = tokens.first else {
                return true
            }
            return !baseTokens.contains(token)
                || stopTokens.contains(token)
                || removableTokens.contains(token)
        }
    }

    private static func quotedSpans(in text: String) -> [String] {
        var spans: [String] = []
        var currentQuote: Character?
        var currentSpan = ""

        for character in text {
            if let quoteEnd = matchingQuoteEnd(for: currentQuote) {
                if character == quoteEnd {
                    spans.append(currentSpan)
                    currentQuote = nil
                    currentSpan = ""
                } else {
                    currentSpan.append(character)
                }
                continue
            }

            if quoteStartCharacters.contains(character) {
                currentQuote = character
            }
        }

        return spans
    }

    private static func matchingQuoteEnd(for quote: Character?) -> Character? {
        switch quote {
        case "\"":
            return "\""
        case "“":
            return "”"
        default:
            return nil
        }
    }

    private static func containsMarkupTag(_ text: String) -> Bool {
        text.range(
            of: #"</?[A-Za-z][A-Za-z0-9-]*\b[^>]*>"#,
            options: .regularExpression
        ) != nil
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
        let baseTokens = wordTokens(base)
        let candidateTokens = wordTokens(candidate)

        if normalizedBase.contains(" can you "), normalizedCandidate.contains(" i can ") {
            return true
        }
        if baseTokens.contains("you"), !candidateTokens.contains("you"),
            candidateTokens.contains("i")
        {
            return true
        }
        if isCommandOrRequest(baseTokens), startsWithAssistantOffer(candidateTokens) {
            return true
        }
        if introducesNewModalCommitment(candidateTokens: candidateTokens, baseTokens: baseTokens) {
            return true
        }
        return false
    }

    private static func startsWithAssistantOffer(_ tokens: [String]) -> Bool {
        starts(tokens, with: ["i", "can"])
            || starts(tokens, with: ["i", "will"])
            || starts(tokens, with: ["i", "would"])
            || starts(tokens, with: ["i'll"])
            || starts(tokens, with: ["we", "can"])
            || starts(tokens, with: ["we", "will"])
            || starts(tokens, with: ["we", "would"])
            || starts(tokens, with: ["we'll"])
    }

    private static func introducesNewModalCommitment(candidateTokens: [String], baseTokens: [String]) -> Bool {
        let baseCounts = tokenCounts(baseTokens.filter { modalCommitmentTokens.contains($0) })
        let candidateCounts = tokenCounts(candidateTokens.filter { modalCommitmentTokens.contains($0) })

        return candidateCounts.contains { token, count in
            count > (baseCounts[token] ?? 0)
        }
    }

    private static func isCommandOrRequest(_ tokens: [String]) -> Bool {
        guard let first = tokens.first else {
            return false
        }
        if starts(tokens, with: ["can", "you"])
            || starts(tokens, with: ["could", "you"])
            || starts(tokens, with: ["would", "you"])
        {
            return true
        }
        if first == "please", tokens.count > 1 {
            return true
        }
        return imperativeLeadTokens.contains(first)
    }

    private static func dropsRequestRecipient(candidate: String, base: String) -> Bool {
        let baseTokens = wordTokens(base)
        let candidateTokens = Set(wordTokens(candidate))

        for index in baseTokens.indices where requestRecipientTokens.contains(baseTokens[index]) {
            guard index > 0 else {
                continue
            }
            if requestRecipientVerbs.contains(baseTokens[index - 1]),
                !candidateTokens.contains(baseTokens[index])
            {
                return true
            }
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

    private static func dropsMeaningfulLike(candidate: String, base: String) -> Bool {
        let baseTokens = wordTokens(base)
        guard baseTokens.contains("like"), !wordTokens(candidate).contains("like") else {
            return false
        }

        for index in baseTokens.indices where baseTokens[index] == "like" {
            if !isLikelyFillerLike(at: index, in: baseTokens) {
                return true
            }
        }

        return false
    }

    private static func isLikelyFillerLike(at index: Int, in tokens: [String]) -> Bool {
        let previous = index > 0 ? tokens[index - 1] : nil
        let previousPrevious = index > 1 ? tokens[index - 2] : nil
        let next = index < tokens.count - 1 ? tokens[index + 1] : nil

        if previous == nil {
            return true
        }
        if previous == "like" || next == "like" {
            return true
        }
        if let previous, fillerLikePreviousTokens.contains(previous) {
            return true
        }
        if previous == "you",
            let previousPrevious,
            fillerLikePreviousTokens.contains(previousPrevious)
                || requestFramePreviousTokens.contains(previousPrevious)
        {
            return true
        }
        return false
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

    private static func retainsRequiredSourceTokens(candidate: String, base: String) -> Bool {
        let baseTokens = wordTokens(base)
        guard correctionMarkerRanges(in: baseTokens).isEmpty else {
            return true
        }

        let requiredTokens = Set(meaningfulTokens(base).filter { !removableTokens.contains($0) })
        guard !requiredTokens.isEmpty else {
            return true
        }

        let candidateTokens = Set(meaningfulTokens(candidate))
        return requiredTokens.isSubset(of: candidateTokens)
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

    private static func starts(_ tokens: [String], with prefix: [String]) -> Bool {
        guard tokens.count >= prefix.count else {
            return false
        }
        return Array(tokens.prefix(prefix.count)) == prefix
    }

    private static func tokenCounts(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
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
        "um", "uh", "er", "oops", "wait", "no", "sorry", "scratch", "actually", "maybe", "please",
        "like", "basically", "literally",
    ]

    private static let fillerLikePreviousTokens: Set<String> = [
        "am", "are", "be", "been", "being", "i'm", "is", "it's", "that's", "they're",
        "was", "we're", "were", "you're",
    ]

    private static let quoteStartCharacters: Set<Character> = [
        "\"", "“",
    ]

    private static let requestFramePreviousTokens: Set<String> = [
        "can", "could", "should", "will", "would",
    ]

    private static let modalCommitmentTokens: Set<String> = [
        "can", "could", "should", "will", "would",
    ]

    private static let imperativeLeadTokens: Set<String> = [
        "add", "book", "build", "change", "check", "clean", "create", "delete", "draft",
        "draw", "fix", "give", "have", "make", "move", "open", "register", "remove",
        "send", "set", "show", "summarize", "tell", "turn", "update", "write",
    ]

    private static let requestRecipientTokens: Set<String> = [
        "me", "us",
    ]

    private static let requestRecipientVerbs: Set<String> = [
        "build", "create", "draft", "draw", "give", "make", "send", "show", "tell",
        "write",
    ]
}
