import XCTest
@testable import ShoutOutCore

final class TextInsertionFormatterTests: XCTestCase {
    func testEmptyContextPastesExactText() {
        XCTAssertEqual(format("hello", before: nil, after: nil).text, "hello")
    }

    func testCursorAfterExistingWordAddsLeadingSpace() {
        XCTAssertEqual(format("world", before: "o", after: nil).text, " world")
    }

    func testCursorBeforeExistingWordAddsTrailingSpace() {
        XCTAssertEqual(format("hello", before: nil, after: "w").text, "hello ")
    }

    func testCursorBetweenWordsAddsBothSpaces() {
        XCTAssertEqual(format("there", before: "i", after: "f").text, " there ")
    }

    func testExistingWhitespacePreventsExtraSpaces() {
        XCTAssertEqual(format("there", before: " ", after: nil).text, "there")
        XCTAssertEqual(format("there", before: nil, after: " ").text, "there")
    }

    func testPunctuationHugsAdjacentText() {
        XCTAssertEqual(format(".", before: "d", after: nil).text, ".")
        XCTAssertEqual(format("hello", before: nil, after: ".").text, "hello")
    }

    func testUnavailableContextFallsBackToTrailingSpace() {
        let result = TextInsertionFormatter.prepare(
            "hello",
            context: nil,
            options: TextInsertionFormattingOptions(appendTrailingSpace: true, useSmartSpacing: true)
        )

        XCTAssertEqual(result.text, "hello ")
        XCTAssertEqual(result.strategy, "fallbackTrailing")
    }

    func testSmartSpacingCanBeDisabledForFallback() {
        let result = TextInsertionFormatter.prepare(
            "hello",
            context: TextInsertionContext(characterBefore: nil, characterAfter: nil),
            options: TextInsertionFormattingOptions(appendTrailingSpace: true, useSmartSpacing: false)
        )

        XCTAssertEqual(result.text, "hello ")
        XCTAssertEqual(result.strategy, "trailing")
    }

    func testSpacingCanBeDisabled() {
        let result = TextInsertionFormatter.prepare(
            "hello",
            context: TextInsertionContext(characterBefore: "x", characterAfter: nil),
            options: TextInsertionFormattingOptions(appendTrailingSpace: false, useSmartSpacing: true)
        )

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.strategy, "exact")
    }

    func testUTF16SelectionContextHandlesEmoji() {
        let text = "hi 👋world"
        let cursor = (text as NSString).range(of: "world").location
        let context = TextInsertionContext(
            text: text,
            selectedUTF16Range: NSRange(location: cursor, length: 0)
        )

        XCTAssertEqual(context?.characterBefore, "👋")
        XCTAssertEqual(context?.characterAfter, "w")
    }

    private func format(
        _ text: String,
        before: Character?,
        after: Character?
    ) -> TextInsertionFormattingResult {
        TextInsertionFormatter.prepare(
            text,
            context: TextInsertionContext(characterBefore: before, characterAfter: after)
        )
    }
}
