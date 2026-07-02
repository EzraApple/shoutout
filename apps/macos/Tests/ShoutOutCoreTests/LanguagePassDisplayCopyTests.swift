import ShoutOutCore
import XCTest

final class LanguagePassDisplayCopyTests: XCTestCase {
    func testDroppedContentReadsAsNoCleanupNecessary() {
        XCTAssertEqual(
            LanguagePassDisplayCopy.status(
                accepted: false,
                changed: false,
                fallbackReason: "dropped_content"
            ),
            "No cleanup necessary"
        )
        XCTAssertEqual(
            LanguagePassDisplayCopy.reason(
                accepted: false,
                changed: false,
                fallbackReason: "dropped_content",
                styleRawValue: "casual"
            ),
            "Meaning protected · Original kept"
        )
        XCTAssertEqual(LanguagePassDisplayCopy.toneTitle("casual"), "Casual")
    }

    func testAcceptedChangeReadsAsCleanedWithPlainReason() {
        XCTAssertEqual(
            LanguagePassDisplayCopy.status(
                accepted: true,
                changed: true,
                fallbackReason: nil
            ),
            "Cleaned"
        )
        XCTAssertEqual(
            LanguagePassDisplayCopy.reason(
                accepted: true,
                changed: true,
                fallbackReason: nil,
                styleRawValue: "formal"
            ),
            "Meaning preserved · Tone applied"
        )
    }

    func testUnchangedAcceptedTextReadsAsNoCleanupNecessary() {
        XCTAssertEqual(
            LanguagePassDisplayCopy.status(
                accepted: true,
                changed: false,
                fallbackReason: nil
            ),
            "No cleanup necessary"
        )
        XCTAssertEqual(
            LanguagePassDisplayCopy.reason(
                accepted: true,
                changed: false,
                fallbackReason: nil,
                styleRawValue: "standard"
            ),
            "Meaning + tone matched"
        )
    }

    func testSummaryDoesNotExposeInternalFallbackSlug() {
        let summary = LanguagePassDisplayCopy.summary(
            accepted: false,
            changed: false,
            fallbackReason: "perspective_shift",
            wallMs: 174,
            styleRawValue: "casual"
        )

        XCTAssertEqual(summary, "No cleanup necessary · Casual · 174ms")
        XCTAssertFalse(summary.contains("perspective_shift"))
    }

    func testDidChangeComparesTrimmedInputAndOutput() {
        XCTAssertTrue(
            LanguagePassDisplayCopy.didChange(
                input: "um can you send this",
                output: "Can you send this?"
            )
        )
        XCTAssertFalse(
            LanguagePassDisplayCopy.didChange(
                input: "Already clean ",
                output: "Already clean"
            )
        )
    }
}
