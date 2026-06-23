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

    func testMidSentenceInsertionLowercasesCommonDictationStarter() {
        let context = TextInsertionContext(
            text: "I think  would work",
            selectedUTF16Range: NSRange(location: 8, length: 0)
        )

        let result = TextInsertionFormatter.prepare("This is good", context: context)

        XCTAssertEqual(result.text, "this is good")
    }

    func testMidSentenceInsertionKeepsLikelyProperNoun() {
        let context = TextInsertionContext(
            text: "send it to  today",
            selectedUTF16Range: NSRange(location: 11, length: 0)
        )

        let result = TextInsertionFormatter.prepare("Ezra", context: context)

        XCTAssertEqual(result.text, "Ezra")
    }

    func testMidSentenceInsertionKeepsAcronym() {
        let context = TextInsertionContext(
            text: "use the  endpoint",
            selectedUTF16Range: NSRange(location: 8, length: 0)
        )

        let result = TextInsertionFormatter.prepare("API", context: context)

        XCTAssertEqual(result.text, "API")
    }

    func testSentenceStartUppercasesCommonStarter() {
        let context = TextInsertionContext(
            text: "ship it.  next",
            selectedUTF16Range: NSRange(location: 9, length: 0)
        )

        let result = TextInsertionFormatter.prepare("this works", context: context)

        XCTAssertEqual(result.text, "This works")
    }

    func testCapitalizationFittingCanBeDisabledForCasualOutput() {
        let context = TextInsertionContext(
            text: "ship it.  next",
            selectedUTF16Range: NSRange(location: 9, length: 0)
        )

        let result = TextInsertionFormatter.prepare(
            "this works",
            context: context,
            options: TextInsertionFormattingOptions(fitCapitalization: false)
        )

        XCTAssertEqual(result.text, "this works")
        XCTAssertEqual(result.strategy, "smart")
    }

    func testNewLineStartsSentenceForCapitalization() {
        let context = TextInsertionContext(
            text: "notes:\n",
            selectedUTF16Range: NSRange(location: 7, length: 0)
        )

        let result = TextInsertionFormatter.prepare("this works", context: context)

        XCTAssertEqual(result.text, "This works")
    }

    func testCodeLikeTextDoesNotChangeCapitalization() {
        let context = TextInsertionContext(
            text: "let value = ",
            selectedUTF16Range: NSRange(location: 12, length: 0)
        )

        let result = TextInsertionFormatter.prepare("This works", context: context)

        XCTAssertEqual(result.text, "This works")
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
        XCTAssertEqual(context?.textBefore, "hi 👋")
        XCTAssertEqual(context?.textAfter, "world")
    }

    func testPlaceholderValueIsTreatedAsEmptyText() {
        let snapshot = TextInsertionTargetSnapshot(
            text: "Ask for follow-up changes",
            selectedUTF16Range: NSRange(location: 0, length: 0),
            placeholder: "Ask for follow-up changes",
            characterCount: 0
        )

        XCTAssertTrue(snapshot.isPlaceholderValue)
        XCTAssertEqual(snapshot.editableText, "")
        XCTAssertEqual(snapshot.editableSelectedUTF16Range, NSRange(location: 0, length: 0))
        XCTAssertEqual(
            TextInsertionFormatter.prepare("ship this", context: snapshot.context).text,
            "ship this"
        )
    }

    func testKnownEmptyComposerPlaceholderIsTreatedAsEmptyTextWithoutPlaceholderAttribute() {
        let snapshot = TextInsertionTargetSnapshot(
            text: "Ask for follow-up changes",
            selectedUTF16Range: NSRange(location: 0, length: 0)
        )

        XCTAssertTrue(snapshot.isPlaceholderValue)
        XCTAssertEqual(snapshot.editableText, "")
    }

    func testPlaceholderLikeRealTextIsPreservedWhenCharacterCountIsNonzero() {
        let snapshot = TextInsertionTargetSnapshot(
            text: "Ask for follow-up changes",
            selectedUTF16Range: NSRange(location: 4, length: 0),
            placeholder: "Ask for follow-up changes",
            characterCount: 25
        )

        XCTAssertFalse(snapshot.isPlaceholderValue)
        XCTAssertEqual(snapshot.editableText, "Ask for follow-up changes")
        XCTAssertEqual(snapshot.context?.characterBefore, " ")
        XCTAssertEqual(snapshot.context?.characterAfter, "f")
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
