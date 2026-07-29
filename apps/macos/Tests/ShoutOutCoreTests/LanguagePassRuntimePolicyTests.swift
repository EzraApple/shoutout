import XCTest
@testable import ShoutOutCore

final class LanguagePassRuntimePolicyTests: XCTestCase {
    func testCasualFallbackAppliesForEveryObservedFailureClass() {
        let base = "You don't need to do any work with the browser."
        let expected = "you don't need to do any work with the browser"
        let reasons = [
            "dropped_content",
            "perspective_shift",
            "unsafe_length_ratio",
            "unresolved_correction",
            "generation_failed",
            "model_not_ready",
            "cancelled",
        ]

        for reason in reasons {
            let fallback = LanguagePassFallbackPolicy.fallback(
                baseText: base,
                candidateText: "can you send this over when you get a chance",
                reason: reason,
                style: .casual
            )

            XCTAssertEqual(fallback?.finalText, expected, reason)
            XCTAssertEqual(fallback?.reason, "mechanical_after_\(reason)", reason)
            XCTAssertTrue(fallback?.changed == true, reason)
        }
    }

    func testFallbackDiscardsPromptLeakButRetainsWholeSource() {
        let base =
            "Also noticing the occasional lack of tone transformation. Some are getting lowercased, but some aren't. I don't know the difference between them."
        let leakedCandidate = """
        can you send this over when you get a chance
        i think this is ready to ship
        also noticing the occasional lack of tone transformation
        """

        let fallback = LanguagePassFallbackPolicy.fallback(
            baseText: base,
            candidateText: leakedCandidate,
            reason: "perspective_shift",
            style: .casual
        )

        XCTAssertEqual(
            fallback?.finalText,
            "also noticing the occasional lack of tone transformation some are getting lowercased but some aren't i don't know the difference between them"
        )
        XCTAssertFalse(fallback?.finalText.contains("send this over") == true)
        XCTAssertFalse(fallback?.finalText.contains("ready to ship") == true)
        XCTAssertEqual(fallback?.candidateText, leakedCandidate)
    }

    func testFallbackRetainsExactObservedLongTranscriptSizes() {
        for wordCount in [290, 1_076] {
            let base = historyShapedWords(wordCount)
            let fallback = LanguagePassFallbackPolicy.fallback(
                baseText: base,
                candidateText: "historystart detail2 detail3",
                reason: "unsafe_length_ratio",
                style: .casual
            )

            let outputWords = fallback?.finalText.split(separator: " ") ?? []
            XCTAssertEqual(outputWords.count, wordCount)
            XCTAssertEqual(outputWords.first, "historystart")
            XCTAssertEqual(outputWords[wordCount / 2], "historymiddle")
            XCTAssertEqual(outputWords.last, "historyend")
        }
    }

    func testNonCasualStylesStillFailClosed() {
        XCTAssertNil(
            LanguagePassFallbackPolicy.fallback(
                baseText: "Keep this unchanged.",
                candidateText: nil,
                reason: "generation_failed",
                style: .standard
            )
        )
        XCTAssertNil(
            LanguagePassFallbackPolicy.fallback(
                baseText: "Keep this unchanged.",
                candidateText: nil,
                reason: "generation_failed",
                style: .formal
            )
        )
    }

    func testGenerationBudgetScalesAcrossObservedTranscriptLengths() {
        let short = LanguagePassGenerationBudget.forText(words(29))
        let medium = LanguagePassGenerationBudget.forText(words(290))
        let long = LanguagePassGenerationBudget.forText(words(1_076))

        XCTAssertEqual(short.maxTokens, 128)
        XCTAssertEqual(short.maxKVSize, 2_048)
        XCTAssertEqual(short.timeoutNanoseconds, 1_200_000_000)

        XCTAssertEqual(medium.maxTokens, 525)
        XCTAssertEqual(medium.maxKVSize, 3_072)
        XCTAssertEqual(medium.timeoutNanoseconds, 2_000_000_000)

        XCTAssertEqual(long.maxTokens, 1_024)
        XCTAssertEqual(long.maxKVSize, 4_096)
        XCTAssertEqual(long.timeoutNanoseconds, 4_000_000_000)
    }

    private func words(_ count: Int) -> String {
        (1...count).map { "word\($0)" }.joined(separator: " ")
    }

    private func historyShapedWords(_ count: Int) -> String {
        var values = (1...count).map { "detail\($0)" }
        values[0] = "Historystart"
        values[count / 2] = "historymiddle"
        values[count - 1] = "historyend."
        return values.joined(separator: " ")
    }
}
