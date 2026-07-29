import Foundation

public struct TranscriptWordTiming: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let probability: Float

    public init(text: String, start: TimeInterval, end: TimeInterval, probability: Float) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }
}

public struct TerminalHallucinationCleanup: Equatable, Sendable {
    public let text: String
    public let candidatePhrase: String?
    public let removed: Bool
    public let gapSeconds: TimeInterval?
    public let meanProbability: Float?
    public let suffixRMS: Float?
    public let precedingRMS: Float?
}

public enum TranscriptHallucinationFilter {
    private static let lowInformationCaptureDuration: TimeInterval = 3.0
    private static let lowEnergyRMS: Float = 0.0025
    private static let lowEnergyPeak: Float = 0.018
    private static let lowInformationWordCount = 2
    private static let lowInformationAlphanumericCount = 24
    private static let terminalGapThreshold: TimeInterval = 0.65
    private static let terminalLowConfidenceThreshold: Float = 0.65

    public static func shouldDrop(
        text: String,
        recordingDuration: TimeInterval,
        signal: AudioSignalAnalysis
    ) -> Bool {
        let info = transcriptInfo(text)
        if info.alphanumericCharacterCount == 0 || info.wordCount == 0 {
            return true
        }

        guard recordingDuration <= lowInformationCaptureDuration else { return false }
        guard signal.rms <= lowEnergyRMS, signal.peak <= lowEnergyPeak else { return false }

        return info.wordCount <= lowInformationWordCount
            && info.alphanumericCharacterCount <= lowInformationAlphanumericCount
    }

    public static func removingTerminalSilenceHallucination(
        from text: String,
        wordTimings: [TranscriptWordTiming],
        audioSamples: [Float],
        sampleRate: Double
    ) -> TerminalHallucinationCleanup {
        let passthrough = TerminalHallucinationCleanup(
            text: text,
            candidatePhrase: nil,
            removed: false,
            gapSeconds: nil,
            meanProbability: nil,
            suffixRMS: nil,
            precedingRMS: nil
        )
        guard sampleRate > 0, !audioSamples.isEmpty else { return passthrough }
        guard let textMatch = terminalPhraseMatch(in: text) else { return passthrough }

        let normalizedWords = wordTimings.map { normalizedWord($0.text) }
        guard normalizedWords.count > textMatch.words.count else {
            return TerminalHallucinationCleanup(
                text: text,
                candidatePhrase: textMatch.phrase,
                removed: false,
                gapSeconds: nil,
                meanProbability: nil,
                suffixRMS: nil,
                precedingRMS: nil
            )
        }
        let suffixStartIndex = normalizedWords.count - textMatch.words.count
        guard Array(normalizedWords[suffixStartIndex...]) == textMatch.words else {
            return TerminalHallucinationCleanup(
                text: text,
                candidatePhrase: textMatch.phrase,
                removed: false,
                gapSeconds: nil,
                meanProbability: nil,
                suffixRMS: nil,
                precedingRMS: nil
            )
        }

        let suffixWords = Array(wordTimings[suffixStartIndex...])
        let precedingWord = wordTimings[suffixStartIndex - 1]
        guard let firstSuffixWord = suffixWords.first, let lastSuffixWord = suffixWords.last else {
            return passthrough
        }

        let gap = max(0, firstSuffixWord.start - precedingWord.end)
        let meanProbability = suffixWords.map(\.probability).reduce(0, +) / Float(suffixWords.count)
        let suffixSignal = signal(
            samples: audioSamples,
            sampleRate: sampleRate,
            start: firstSuffixWord.start,
            end: lastSuffixWord.end
        )
        let precedingSignal = signal(
            samples: audioSamples,
            sampleRate: sampleRate,
            start: max(0, precedingWord.end - 0.6),
            end: precedingWord.end
        )

        let acousticallyQuiet =
            suffixSignal.rms <= max(0.0015, precedingSignal.rms * 0.45)
            && suffixSignal.peak <= max(0.008, precedingSignal.peak * 0.60)
        let shouldRemove =
            gap >= terminalGapThreshold
            && (meanProbability <= terminalLowConfidenceThreshold || acousticallyQuiet)

        return TerminalHallucinationCleanup(
            text: shouldRemove ? textMatch.prefix : text,
            candidatePhrase: textMatch.phrase,
            removed: shouldRemove,
            gapSeconds: gap,
            meanProbability: meanProbability,
            suffixRMS: suffixSignal.rms,
            precedingRMS: precedingSignal.rms
        )
    }

    private struct TerminalPhraseMatch {
        let prefix: String
        let phrase: String
        let words: [String]
    }

    private static func terminalPhraseMatch(in text: String) -> TerminalPhraseMatch? {
        let patterns: [(String, String, [String])] = [
            (#"(?i)[\s,;:–—-]+thank\s+you[.!?]*\s*$"#, "thank_you", ["thank", "you"]),
            (#"(?i)[\s,;:–—-]+thanks[.!?]*\s*$"#, "thanks", ["thanks"]),
        ]

        for (pattern, phrase, words) in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else {
                continue
            }
            let prefix = text[..<range.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { continue }
            return TerminalPhraseMatch(prefix: prefix, phrase: phrase, words: words)
        }
        return nil
    }

    private static func normalizedWord(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func signal(
        samples: [Float],
        sampleRate: Double,
        start: TimeInterval,
        end: TimeInterval
    ) -> AudioSignalAnalysis {
        let lower = min(max(Int(start * sampleRate), 0), samples.count)
        let upper = min(max(Int(end * sampleRate), lower), samples.count)
        guard lower < upper else {
            return AudioSignalAnalysis.analyze(samples: [])
        }
        return AudioSignalAnalysis.analyze(samples: Array(samples[lower..<upper]))
    }

    private struct TranscriptInfo {
        let wordCount: Int
        let alphanumericCharacterCount: Int
    }

    private static func transcriptInfo(_ text: String) -> TranscriptInfo {
        var wordCount = 0
        var alphanumericCharacterCount = 0
        var isInsideWord = false

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                alphanumericCharacterCount += 1
                if !isInsideWord {
                    wordCount += 1
                    isInsideWord = true
                }
            } else {
                isInsideWord = false
            }
        }

        return TranscriptInfo(
            wordCount: wordCount,
            alphanumericCharacterCount: alphanumericCharacterCount
        )
    }
}
