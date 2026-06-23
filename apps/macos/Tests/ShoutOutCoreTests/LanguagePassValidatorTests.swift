import XCTest
@testable import ShoutOutCore

final class LanguagePassValidatorTests: XCTestCase {
    func testExtractsLabeledPlainTextOutput() {
        let output = "Output: Can you send this over when you get a chance?"

        let candidate = LanguagePassValidator.extractCandidate(from: output)

        XCTAssertEqual(candidate, "Can you send this over when you get a chance?")
    }

    func testAcceptsSafeFillerAndRepeatCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "Can you send this over when you get a chance?",
            baseText: "um can you can you send this over when you get a chance"
        )

        XCTAssertEqual(validation.acceptedText, "Can you send this over when you get a chance?")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsAutoPunctuationAndCasing() {
        let validation = LanguagePassValidator.validate(
            output: "I think this works, but maybe we should test it first.",
            baseText: "i think this works but maybe we should test it first"
        )

        XCTAssertEqual(validation.acceptedText, "I think this works, but maybe we should test it first.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsSelfCorrectionCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "I want to meet on Monday.",
            baseText: "i want to meet on tuesday wait no monday"
        )

        XCTAssertEqual(validation.acceptedText, "I want to meet on Monday.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsShortSelfCorrectionCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "I want to meet on Monday.",
            baseText: "i want to meet on tuesday er monday"
        )

        XCTAssertEqual(validation.acceptedText, "I want to meet on Monday.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testLeavesUnchangedCasualWaitNoActuallyPhrasingAsNoOp() {
        let validation = LanguagePassValidator.validate(
            output: "wait no actually make it the smaller one",
            baseText: "wait no actually make it the smaller one"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unchanged")
    }

    func testDeterministicCleanupRemovesArticleBeforeActuallyFalseStart() {
        let input = "Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?"

        let cleaned = LanguagePassDeterministicCleanup.clean(input)

        XCTAssertEqual(
            cleaned,
            "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?"
        )
    }

    func testDeterministicCleanupAppliesCasualStyle() {
        let cleaned = LanguagePassDeterministicCleanup.clean(
            "Can you send this over when you get a chance?",
            style: .casual
        )

        XCTAssertEqual(cleaned, "can you send this over when you get a chance")
    }

    func testDeterministicCleanupRemovesSimpleFillerAndAdjacentRepeats() {
        let cleaned = LanguagePassDeterministicCleanup.clean(
            "um yeah yeah that works can you send it over",
            style: .casual
        )

        XCTAssertEqual(cleaned, "yeah that works can you send it over")
    }

    func testAcceptsDeterministicActuallyFalseStartCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?",
            baseText: "Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?"
        )

        XCTAssertEqual(
            validation.acceptedText,
            "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?"
        )
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsCasualStyleCleanupWithoutCasingOrPunctuation() {
        let validation = LanguagePassValidator.validate(
            output: "yeah that works can you send it over",
            baseText: "um yeah yeah that works can you send it over"
        )

        XCTAssertEqual(validation.acceptedText, "yeah that works can you send it over")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsFormalStyleFormatting() {
        let validation = LanguagePassValidator.validate(
            output: "I can join Monday, probably around three.",
            baseText: "i can join monday probably around three"
        )

        XCTAssertEqual(validation.acceptedText, "I can join Monday, probably around three.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testStylePromptsDescribeFormattingOnly() {
        XCTAssertTrue(LanguagePassPrompt.systemInstructions(for: .casual).contains("lowercase"))
        XCTAssertTrue(LanguagePassPrompt.systemInstructions(for: .formal).contains("word choice"))
    }

    func testUnchangedOutputIsNoOp() {
        let validation = LanguagePassValidator.validate(
            output: "Open the settings panel.",
            baseText: "Open the settings panel."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unchanged")
    }

    func testRejectsAssistantChatter() {
        let validation = LanguagePassValidator.validate(
            output: "Sure, here's the cleaned version: let's meet Monday.",
            baseText: "let's meet monday"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "assistant_chatter")
    }

    func testRejectsUnsafeExpansion() {
        let validation = LanguagePassValidator.validate(
            output: "Let's meet Monday and here are several unrelated extra details that were not in the dictated text.",
            baseText: "let's meet monday"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unsafe_length_ratio")
    }

    func testRejectsNewContentWords() {
        let validation = LanguagePassValidator.validate(
            output: "Open the settings panel and delete the database.",
            baseText: "open the settings panel"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unsafe_length_ratio")
    }

    func testRejectsNewNumbers() {
        let validation = LanguagePassValidator.validate(
            output: "Move the meeting to 4.",
            baseText: "move the meeting"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "new_numbers")
    }

    func testRejectsPromptFormatLeak() {
        let validation = LanguagePassValidator.validate(
            output: "Input: hello\nOutput: Hello.",
            baseText: "hello"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "format_leak")
    }

    func testRejectsUnresolvedCorrectionMarkers() {
        let validation = LanguagePassValidator.validate(
            output: "I want to meet on Tuesday. Wait no Monday.",
            baseText: "i want to meet on tuesday wait no monday"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unresolved_correction")
    }

    func testRejectsBothSidesOfShortCorrection() {
        let validation = LanguagePassValidator.validate(
            output: "I want to meet on Tuesday, and on Monday.",
            baseText: "i want to meet on tuesday er monday"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unresolved_correction")
    }

    func testRejectsDroppedFinalChoiceFromShortCorrection() {
        let validation = LanguagePassValidator.validate(
            output: "I want to meet on Tuesday. Er.",
            baseText: "i want to meet on tuesday er monday"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "unresolved_correction")
    }

    func testRejectsPerspectiveShift() {
        let validation = LanguagePassValidator.validate(
            output: "I can send this over when I get a chance.",
            baseText: "can you send this over when you get a chance"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "perspective_shift")
    }

    func testRejectsDroppedTaskDetails() {
        let validation = LanguagePassValidator.validate(
            output: "Turn on the beta option.",
            baseText: "open the settings panel and turn on the beta option"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }
}
