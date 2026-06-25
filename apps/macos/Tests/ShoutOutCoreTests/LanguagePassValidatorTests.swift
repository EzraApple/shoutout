import XCTest
@testable import ShoutOutCore

final class LanguagePassValidatorTests: XCTestCase {
    func testExtractsLabeledPlainTextOutput() {
        let output = "Output: Can you send this over when you get a chance?"

        let candidate = LanguagePassValidator.extractCandidate(from: output)

        XCTAssertEqual(candidate, "Can you send this over when you get a chance?")
    }

    func testExtractsFirstCandidateLineBeforeModelRunOn() {
        let output = """
        Does this PR also make it actually register manage tabs and the suggestion tool with this thing?

        wait no actually, actually, actually
        """

        let candidate = LanguagePassValidator.extractCandidate(from: output)

        XCTAssertEqual(
            candidate,
            "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?"
        )
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

    func testAcceptsModelActuallyFalseStartCleanup() {
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

    func testAcceptsUnnecessaryLikeFillerCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "I think this is ready to ship.",
            baseText: "i think this is like ready to ship"
        )

        XCTAssertEqual(validation.acceptedText, "I think this is ready to ship.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsOtherDiscourseFillerCleanup() {
        let validation = LanguagePassValidator.validate(
            output: "This is ready to ship.",
            baseText: "this is basically literally ready to ship"
        )

        XCTAssertEqual(validation.acceptedText, "This is ready to ship.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsFillerLikeAfterRequestFrame() {
        let validation = LanguagePassValidator.validate(
            output: "Could you review this when you have time?",
            baseText: "Could you, like, review this when you have time?"
        )

        XCTAssertEqual(validation.acceptedText, "Could you review this when you have time?")
        XCTAssertNil(validation.fallbackReason)
    }

    func testAcceptsDroppingPolitenessMarker() {
        let validation = LanguagePassValidator.validate(
            output: "Drop the random comments.",
            baseText: "Drop the random comments please."
        )

        XCTAssertEqual(validation.acceptedText, "Drop the random comments.")
        XCTAssertNil(validation.fallbackReason)
    }

    func testRejectsDroppingMeaningfulLike() {
        let validation = LanguagePassValidator.validate(
            output: "I this direction.",
            baseText: "I like this direction."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }

    func testRejectsDroppingComparisonLike() {
        let validation = LanguagePassValidator.validate(
            output: "This looks it will work.",
            baseText: "This looks like it will work."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }

    func testRejectsDroppingWouldLike() {
        let validation = LanguagePassValidator.validate(
            output: "I would to join.",
            baseText: "I would like to join."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }

    func testRejectsDroppingJustLikeComparison() {
        let validation = LanguagePassValidator.validate(
            output: "Make it just this.",
            baseText: "Make it just like this."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
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
        XCTAssertTrue(LanguagePassPrompt.systemInstructions(for: .standard).contains("unnecessary \"like\""))
        XCTAssertTrue(LanguagePassPrompt.systemInstructions(for: .standard).contains("Unsafe rewrite patterns"))
        XCTAssertTrue(LanguagePassPrompt.systemInstructions(for: .standard).contains("leading subject phrase"))
        XCTAssertFalse(LanguagePassPrompt.systemInstructions(for: .casual).contains("Good:"))
    }

    func testPromptSelectsFocusedExamplesForInput() {
        let examples = LanguagePassPrompt.examples(
            for: .standard,
            input: "Does this PR also make it a... actually register manage tabs and the suggestion tool with this thing?"
        )

        XCTAssertEqual(examples.count, 1)
        XCTAssertEqual(
            examples.first?.output,
            "Does this PR also make it actually register manage tabs and the suggestion tool with this thing?"
        )
    }

    func testCasualRetryPromptFlagsStyleViolations() {
        let retryPrompt = LanguagePassPrompt.retryPrompt(
            for: "Can you send this over when you get a chance?",
            style: .casual,
            previousOutput: "can you send this over when you get a chance?"
        )

        XCTAssertNotNil(retryPrompt)
        XCTAssertTrue(retryPrompt?.contains("Output: can you send this over when you get a chance") == true)
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

    func testAcceptsImperativeRequestCleanupWithoutChangingIntent() {
        let validation = LanguagePassValidator.validate(
            output: "Make me two pages, one owl-themed and one octopus-themed. Have two sub-agents do it.",
            baseText: "Make me two pages, one owl themed and one octopus themed. Have two sub agents do it."
        )

        XCTAssertEqual(
            validation.acceptedText,
            "Make me two pages, one owl-themed and one octopus-themed. Have two sub-agents do it."
        )
        XCTAssertNil(validation.fallbackReason)
    }

    func testRejectsAssistantOfferForImperativeRequest() {
        let validation = LanguagePassValidator.validate(
            output: "I can make two pages, one owl-themed and one octopus-themed. Two sub-agents will do it.",
            baseText: "Make me two pages, one owl themed and one octopus themed. Have two sub agents do it."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "perspective_shift")
    }

    func testRejectsNewCommitmentForImperativeRequest() {
        let validation = LanguagePassValidator.validate(
            output: "Make me two pages, one owl-themed and one octopus-themed. Two sub-agents will do it.",
            baseText: "Make me two pages, one owl themed and one octopus themed. Have two sub agents do it."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "perspective_shift")
    }

    func testRejectsExtraModalInsideInstructionChain() {
        let validation = LanguagePassValidator.validate(
            output: "Okay, but if I merge this in main, I can just tell that the agent can look at this to help fix this issue.",
            baseText: "Okay, but if I merge this in main, I can just tell that agent to look at this to help fix this issue."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "perspective_shift")
    }

    func testRejectsDroppedRequestRecipient() {
        let validation = LanguagePassValidator.validate(
            output: "Make two pages, one owl-themed and one octopus-themed. Have two sub-agents do it.",
            baseText: "Make me two pages, one owl themed and one octopus themed. Have two sub agents do it."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }

    func testAcceptsQuotedTechnicalTerm() {
        let validation = LanguagePassValidator.validate(
            output: "Can we replace \"synthetic\" with agent-facing text?",
            baseText: "Can we replace synthetic with agent facing text?"
        )

        XCTAssertEqual(
            validation.acceptedText,
            "Can we replace \"synthetic\" with agent-facing text?"
        )
        XCTAssertNil(validation.fallbackReason)
    }

    func testRejectsQuoteSpamAroundFillerAndPhrases() {
        let validation = LanguagePassValidator.validate(
            output: "You shouldn't want to comment asking if we could replace \"synthetic\" with \"like\" agent facing text as \"like a name\".",
            baseText: "You shouldn't want to comment asking if we could replace synthetic with like agent facing text as like a name."
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "suspicious_structure")
    }

    func testRejectsDroppedTaskDetails() {
        let validation = LanguagePassValidator.validate(
            output: "Turn on the beta option.",
            baseText: "open the settings panel and turn on the beta option"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }

    func testRejectsDroppingLeadingSubjectPhrase() {
        let validation = LanguagePassValidator.validate(
            output: "low-key huge can you fix that?",
            baseText: "The diff is low-key huge, can you fix that?"
        )

        XCTAssertNil(validation.acceptedText)
        XCTAssertEqual(validation.fallbackReason, "dropped_content")
    }
}
