import XCTest
@testable import ShoutOutCore

final class TextPostProcessorTests: XCTestCase {
    func testTrimsWhitespace() {
        XCTAssertEqual(process("  hello world  "), "hello world")
    }

    func testRemovesLowercaseUm() {
        XCTAssertEqual(process("um I sent it"), "I sent it")
    }

    func testRemovesUppercaseUh() {
        XCTAssertEqual(process("Uh, that works"), "that works")
    }

    func testRemovesFillerWithTrailingComma() {
        XCTAssertEqual(process("I think, um, this works"), "I think, this works")
    }

    func testPreservesFillerWhenDisabled() {
        let options = TextPostProcessingOptions(removeFillerWords: false)
        XCTAssertEqual(process("um I sent it", options: options), "um I sent it")
    }

    func testRemovesYouKnowFiller() {
        XCTAssertEqual(process("I can, you know, ship this"), "I can, ship this")
    }

    func testCollapsesRepeatedSpaces() {
        XCTAssertEqual(process("hello    world"), "hello world")
    }

    func testReturnsEmptyForWhitespaceInput() {
        XCTAssertEqual(process("    \n\t   "), "")
    }

    func testPreservesExistingPunctuation() {
        XCTAssertEqual(process("Ship this, please."), "Ship this, please.")
    }

    func testReplacesYuXinWithYuxin() {
        XCTAssertEqual(process("I sent this to yu xin"), "I sent this to Yuxin")
    }

    func testReplacesYouShinWithYuxin() {
        XCTAssertEqual(process("ask you shin about it"), "ask Yuxin about it")
    }

    func testReplacesSpelledOutYuxinWithHyphens() {
        XCTAssertEqual(process("send it to Y-U-X-I-N"), "send it to Yuxin")
    }

    func testReplacesSpelledOutYuxinWithSpaces() {
        XCTAssertEqual(process("send it to Y U X I N"), "send it to Yuxin")
    }

    func testDictionaryReplacementIsCaseInsensitive() {
        XCTAssertEqual(process("ask YOU SHIN"), "ask Yuxin")
    }

    func testDictionaryReplacesMultipleOccurrences() {
        XCTAssertEqual(process("yu xin and you shin approved"), "Yuxin and Yuxin approved")
    }

    func testDictionaryDoesNotReplaceInsideOtherWords() {
        XCTAssertEqual(process("bayu xinside stays weird"), "bayu xinside stays weird")
    }

    func testLongerAliasesWinBeforeShorterAliases() {
        let entries = [
            DictionaryEntry(phrase: "Yuxin", aliases: ["yu xin"]),
            DictionaryEntry(phrase: "Xin", aliases: ["xin"]),
        ]
        XCTAssertEqual(process("yu xin said xin is a name", entries: entries), "Yuxin said Xin is a name")
    }

    func testCustomAcronymReplacement() {
        let entries = [DictionaryEntry(phrase: "API", aliases: ["a p i", "A.P.I."])]
        XCTAssertEqual(process("the a p i is ready", entries: entries), "the API is ready")
    }

    func testCustomPhraseReplacement() {
        let entries = [DictionaryEntry(phrase: "Replo", aliases: ["rep low", "reply low"])]
        XCTAssertEqual(process("ship it in rep low"), "ship it in Replo")
        XCTAssertEqual(process("ship it in reply low", entries: entries), "ship it in Replo")
    }

    func testNewLineCommand() {
        XCTAssertEqual(process("first line new line second line"), "first line\nsecond line")
    }

    func testNewParagraphCommand() {
        XCTAssertEqual(process("intro new paragraph next idea"), "intro\n\nnext idea")
    }

    func testPeriodCommand() {
        XCTAssertEqual(process("ship it period next"), "ship it. next")
    }

    func testQuestionMarkCommand() {
        XCTAssertEqual(process("is it ready question mark"), "is it ready?")
    }

    func testExclamationPointCommand() {
        XCTAssertEqual(process("ship it exclamation point"), "ship it!")
    }

    func testDictionaryRunsAfterSpokenCommands() {
        XCTAssertEqual(process("send it to yu xin new line thanks"), "send it to Yuxin\nthanks")
    }

    func testDefaultEntriesIncludeYuxin() {
        XCTAssertTrue(DictionaryEntry.defaultEntries.contains { $0.phrase == "Yuxin" })
    }

    func testDisablesSpokenCommandsWhenRequested() {
        let options = TextPostProcessingOptions(applySpokenCommands: false)
        XCTAssertEqual(process("first new line second", options: options), "first new line second")
    }

    private func process(
        _ text: String,
        options: TextPostProcessingOptions = .default,
        entries: [DictionaryEntry] = DictionaryEntry.defaultEntries
    ) -> String {
        TextPostProcessor.process(text, options: options, dictionaryEntries: entries)
    }
}
