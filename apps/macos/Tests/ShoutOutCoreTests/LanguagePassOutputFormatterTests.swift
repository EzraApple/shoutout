import XCTest
@testable import ShoutOutCore

final class LanguagePassOutputFormatterTests: XCTestCase {
    func testFinalizesAllSafePathsAndPreservesBypasses() {
        for style in LanguagePassStyle.allCases {
            for reason in ["disabled", "empty_input"] {
                let result = LanguagePassOutputFormatter.format(source: "i can wait 2.5", finalText: "i can wait 2.5", style: style, enabled: reason != "disabled", fallbackReason: reason)
                XCTAssertEqual(result.text, "i can wait 2.5")
                XCTAssertFalse(result.numericFallback)
            }
        }
        for style in [LanguagePassStyle.standard, .formal] {
            for reason: String? in [nil, "model_not_ready", "generation_failed", "cancelled", "dropped_content"] {
                let result = LanguagePassOutputFormatter.format(source: "i can wait", finalText: "i can wait", style: style, enabled: true, fallbackReason: reason)
                XCTAssertEqual(result.text, "I can wait")
                XCTAssertFalse(result.numericFallback)
            }
        }
        let rejectedNumber = LanguagePassOutputFormatter.format(source: "Um, keep 2.5!", finalText: "keep 2 5", style: .casual, enabled: true, fallbackReason: nil)
        XCTAssertEqual(rejectedNumber.text, "keep 2.5")
        XCTAssertTrue(rejectedNumber.numericFallback)
        let rejectedContent = LanguagePassOutputFormatter.format(source: "Um, keep 2.5!", finalText: "unsafe output", style: .casual, enabled: true, fallbackReason: "dropped_content")
        XCTAssertEqual(rejectedContent.text, "keep 2.5")
        XCTAssertFalse(rejectedContent.numericFallback)
        let accepted = LanguagePassOutputFormatter.format(source: "Um, keep 2.5!", finalText: "keep 2.5", style: .casual, enabled: true, fallbackReason: nil)
        XCTAssertEqual(accepted.text, "keep 2.5")
        XCTAssertFalse(accepted.numericFallback)
    }

    func testCasesProseWithoutChangingWordsOrGuessingEndings() {
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("i can't publish. can you check? i will wait"), "I can't publish. Can you check? I will wait")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("the draft is"), "The draft is")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("what we need is a fix"), "What we need is a fix")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("send it on tuesday sorry wednesday"), "Send it on tuesday sorry wednesday")
    }

    func testProtectsTechnicalTokensAndAbbreviations() {
        for source in ["iOS is ready", "user_id is stable", "userId is stable", "git status", "i = 0", "src/auth.ts is missing", "`i` is a variable", "https://example.com is the url"] {
            XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase(source), source, source)
        }
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("ask Dr. smith about version 2.5. i will wait"), "Ask Dr. smith about version 2.5. I will wait")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("```swift\ni = 0\n```\ni will wait"), "```swift\ni = 0\n```\nI will wait")
    }

    func testProtectsNumbersInCasualFallback() {
        XCTAssertEqual(LanguagePassOutputFormatter.casualFallback("Um, keep version 2.0 and 1.x. Pay $160,000, not $16,000!"), "keep version 2.0 and 1.x pay $160,000 not $16,000")
        XCTAssertEqual(LanguagePassOutputFormatter.casualFallback("Set it to -3.5, then +2.5. Keep 50% and 2026-09-18."), "set it to -3.5 then +2.5 keep 50% and 2026-09-18")
    }

    func testRejectsDamagedNumericTokens() {
        XCTAssertFalse(LanguagePassOutputFormatter.preservesNumbers(source: "version 2.5", candidate: "version 2 5"))
        XCTAssertFalse(LanguagePassOutputFormatter.preservesNumbers(source: "set -15", candidate: "set 15"))
        XCTAssertFalse(LanguagePassOutputFormatter.preservesNumbers(source: "2.5", candidate: "12.50"))
        XCTAssertFalse(LanguagePassOutputFormatter.preservesNumbers(source: "2.5 and 2.5", candidate: "2.5"))
        XCTAssertTrue(LanguagePassOutputFormatter.preservesNumbers(source: "Version 2.5!", candidate: "version 2.5"))
    }

    func testHandlesUnicodeAndIsIdempotent() {
        for text in ["“i will ask José.” i can wait", "🦀 i will wait. i won't publish", "\u{E000}0\u{E001} version 2.5", "i can check\n\ni will wait"] {
            let result = LanguagePassOutputFormatter.sentenceCase(text)
            XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase(result), result)
            let casual = LanguagePassOutputFormatter.casualFallback(text)
            XCTAssertEqual(LanguagePassOutputFormatter.casualFallback(casual), casual)
        }
    }

    func testDoesNotMistakeUnquotedIndexForPronoun() {
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("replace i with j"), "Replace i with j")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("set i to zero"), "Set i to zero")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("i is the index"), "i is the index")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("i will wait while i is less than ten"), "I will wait while i is less than ten")
    }

    func testDoesNotInterpretAbbreviationsAsSentenceEndings() {
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("read the U.S. docs. i can wait"), "Read the U.S. docs. I can wait")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("keep it simple e.g. use the default"), "Keep it simple e.g. use the default")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("echo hello"), "echo hello")
        XCTAssertEqual(LanguagePassOutputFormatter.sentenceCase("rg foo src"), "rg foo src")
    }
}
