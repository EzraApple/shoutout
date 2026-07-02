import XCTest
@testable import ShoutOutCore

final class LanguagePassMechanicalNormalizerTests: XCTestCase {
    func testRemovesOnlyAbandonedArticleBeforeActually() {
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("Does this make it a... actually work?"),
            "Does this make it actually work?"
        )
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("Does this make it an… actually supported case?"),
            "Does this make it actually supported case?"
        )
    }

    func testRemovesStandaloneFillersWithoutPhraseBans() {
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("Um, can you send it, uh, today?"),
            "can you send it today?"
        )
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("This is er important."),
            "This is important."
        )
    }

    func testCollapsesOnlyConservativeRepeatedStarts() {
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("Can you can you send this over?"),
            "Can you send this over?"
        )
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("I I think this works."),
            "I think this works."
        )
    }

    func testDoesNotHandleSemanticCorrectionsOrToneCleanup() {
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("I want Tuesday wait no Monday."),
            "I want Tuesday wait no Monday."
        )
        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize("Can you, like, basically please check this?"),
            "Can you, like, basically please check this?"
        )
    }

    func testIsIdempotent() {
        let text = "Can you send this over today?"

        XCTAssertEqual(
            LanguagePassMechanicalNormalizer.normalize(LanguagePassMechanicalNormalizer.normalize(text)),
            text
        )
    }
}
