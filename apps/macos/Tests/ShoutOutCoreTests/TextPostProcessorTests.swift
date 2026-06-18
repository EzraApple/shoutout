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

    func testDisablesSpokenCommandsWhenRequested() {
        let options = TextPostProcessingOptions(applySpokenCommands: false)
        XCTAssertEqual(process("first new line second", options: options), "first new line second")
    }

    private func process(
        _ text: String,
        options: TextPostProcessingOptions = .default
    ) -> String {
        TextPostProcessor.process(text, options: options)
    }
}
