public struct LanguagePassFallback: Equatable, Sendable {
    public let finalText: String
    public let candidateText: String?
    public let reason: String
    public let changed: Bool
}

public enum LanguagePassFallbackPolicy {
    public static func fallback(
        baseText: String,
        candidateText: String?,
        reason: String,
        style: LanguagePassStyle
    ) -> LanguagePassFallback? {
        guard style == .casual else { return nil }

        let finalText = LanguagePassMechanicalNormalizer.normalize(baseText, style: style)
        guard !finalText.isEmpty else { return nil }

        return LanguagePassFallback(
            finalText: finalText,
            candidateText: candidateText,
            reason: "mechanical_after_\(reason)",
            changed: finalText != baseText
        )
    }
}

public struct LanguagePassGenerationBudget: Equatable, Sendable {
    public let maxTokens: Int
    public let maxKVSize: Int
    public let timeoutNanoseconds: UInt64

    public static func forText(_ text: String) -> LanguagePassGenerationBudget {
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        let maxTokens = min(1_024, max(128, Int(Double(max(1, wordCount)) * 1.7) + 32))

        let maxKVSize: Int
        if wordCount >= 360 {
            maxKVSize = 4_096
        } else if wordCount >= 160 {
            maxKVSize = 3_072
        } else {
            maxKVSize = 2_048
        }

        let extraChunks = max(0, wordCount - 80) / 80
        let timeout = 1_200_000_000 + UInt64(extraChunks) * 400_000_000

        return LanguagePassGenerationBudget(
            maxTokens: maxTokens,
            maxKVSize: maxKVSize,
            timeoutNanoseconds: min(timeout, 4_000_000_000)
        )
    }
}
