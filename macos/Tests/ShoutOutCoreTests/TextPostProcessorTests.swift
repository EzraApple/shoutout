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

    func testDefaultPreservesSelfCorrectionPhrases() {
        XCTAssertEqual(
            process("when I press the boom scratch that press function"),
            "when I press the boom scratch that press function"
        )
        XCTAssertEqual(process("let's meet at 2 scratch that 3"), "let's meet at 2 scratch that 3")
    }

    func testCanRewriteRepeatedActionSelfCorrectionWhenEnabled() {
        let options = TextPostProcessingOptions(cleanUpSelfCorrections: true)
        XCTAssertEqual(
            process("when I press the boom scratch that press function", options: options),
            "when I press function"
        )
    }

    func testCanRewritePrepositionSelfCorrectionWhenEnabled() {
        let options = TextPostProcessingOptions(cleanUpSelfCorrections: true)
        XCTAssertEqual(process("let's meet at 2 scratch that 3", options: options), "let's meet at 3")
    }

    func testPreservesActuallyWhenItIsNotACorrection() {
        XCTAssertEqual(process("I actually liked it"), "I actually liked it")
    }

    func testPreservesActuallyInCorrectionLikePhrase() {
        XCTAssertEqual(process("let's meet at 2 actually 3"), "let's meet at 2 actually 3")
    }

    func testPreservesIMeanInCorrectionLikePhrase() {
        XCTAssertEqual(
            process("when I press the boom oh I mean or press function rather"),
            "when I press the boom oh I mean or press function rather"
        )
    }

    func testDisablesSelfCorrectionCleanupWhenRequested() {
        let options = TextPostProcessingOptions(cleanUpSelfCorrections: false)
        XCTAssertEqual(
            process("when I press the boom scratch that press function", options: options),
            "when I press the boom scratch that press function"
        )
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

    func testReplacesRepLowWithReplo() {
        XCTAssertEqual(process("I shipped this in rep low"), "I shipped this in Replo")
    }

    func testReplacesReplyLowWithReplo() {
        XCTAssertEqual(process("open reply low"), "open Replo")
    }

    func testReplacesLineEarWithLinear() {
        XCTAssertEqual(process("file this in line ear"), "file this in Linear")
    }

    func testDictionaryReplacementIsCaseInsensitive() {
        XCTAssertEqual(process("open REP LOW"), "open Replo")
    }

    func testDictionaryReplacesMultipleOccurrences() {
        XCTAssertEqual(process("rep low and reply low shipped"), "Replo and Replo shipped")
    }

    func testDictionaryDoesNotReplaceInsideOtherWords() {
        XCTAssertEqual(process("bare placement stays weird"), "bare placement stays weird")
    }

    func testLongerAliasesWinBeforeShorterAliases() {
        let entries = [
            DictionaryEntry(phrase: "Jane Doe", aliases: ["jane doe"]),
            DictionaryEntry(phrase: "Doe", aliases: ["doe"]),
        ]
        XCTAssertEqual(process("jane doe said doe is ready", entries: entries), "Jane Doe said Doe is ready")
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
        XCTAssertEqual(process("send it to rep low new line thanks"), "send it to Replo\nthanks")
    }

    func testDefaultEntriesIncludeProductTerms() {
        XCTAssertTrue(DictionaryEntry.defaultEntries.contains { $0.phrase == "Replo" })
        XCTAssertTrue(DictionaryEntry.defaultEntries.contains { $0.phrase == "Linear" })
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
