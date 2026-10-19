import XCTest
@testable import ShoutOutCore

final class DictionaryReplacerTests: XCTestCase {
    func testMatchesCaseInsensitivelyAndPreservesSurroundingText() {
        let entries = [DictionaryEntry(phrase: "ShoutOut", aliases: ["shout out"])]
        XCTAssertEqual(
            DictionaryReplacer.replace("(SHOUT OUT), then shout out!", entries: entries),
            "(ShoutOut), then ShoutOut!"
        )
    }

    func testUsesUnicodeWholePhraseBoundaries() {
        let entries = [DictionaryEntry(phrase: "Café", aliases: ["cafe"])]
        XCTAssertEqual(
            DictionaryReplacer.replace("cafe cafés café café _cafe cafe_ cafe1 1cafe", entries: entries),
            "Café cafés café café _cafe cafe_ cafe1 1cafe"
        )
        let cjk = [DictionaryEntry(phrase: "東京", aliases: ["とうきょう"])]
        XCTAssertEqual(
            DictionaryReplacer.replace("(とうきょう)とうきょう駅", entries: cjk),
            "(東京)とうきょう駅"
        )
    }

    func testMatchesUnicodeLettersWithoutCaseSensitivity() {
        let entries = [DictionaryEntry(phrase: "Café", aliases: ["café"])]
        XCTAssertEqual(DictionaryReplacer.replace("CAFÉ!", entries: entries), "Café!")
    }

    func testLongerOverlappingAliasWins() {
        let entries = [
            DictionaryEntry(phrase: "Jane", aliases: ["jane"]),
            DictionaryEntry(phrase: "Jane Doe", aliases: ["jane doe"]),
        ]
        XCTAssertEqual(
            DictionaryReplacer.replace("jane doe met jane.", entries: entries),
            "Jane Doe met Jane."
        )
    }

    func testLongerOverlapWinsEvenWhenItStartsLater() {
        let entries = [
            DictionaryEntry(phrase: "First", aliases: ["new york"]),
            DictionaryEntry(phrase: "Second", aliases: ["york city"]),
        ]
        XCTAssertEqual(DictionaryReplacer.replace("new york city", entries: entries), "new Second")
    }

    func testEarlierEntryWinsEqualLengthOverlap() {
        let entries = [
            DictionaryEntry(phrase: "First", aliases: ["abc"]),
            DictionaryEntry(phrase: "Second", aliases: ["ABC"]),
        ]
        XCTAssertEqual(DictionaryReplacer.replace("abc", entries: entries), "First")
    }

    func testReplacementsNeverCascadeOrReprocessOutputs() {
        let entries = [
            DictionaryEntry(phrase: "new york", aliases: ["nyc"]),
            DictionaryEntry(phrase: "NY", aliases: ["new york"]),
        ]
        XCTAssertEqual(
            DictionaryReplacer.replace("nyc and new york", entries: entries),
            "new york and NY"
        )
    }

    func testReplacementSyntaxIsLiteral() {
        let entries = [DictionaryEntry(phrase: #"$1 \folder"#, aliases: ["folder"])]
        XCTAssertEqual(
            DictionaryReplacer.replace("folder. folder", entries: entries),
            #"$1 \folder. $1 \folder"#
        )
    }

    func testLegacyEmptyAliasIsIgnored() {
        let entries = [DictionaryEntry(phrase: "No-op", aliases: [""])]
        XCTAssertEqual(DictionaryReplacer.replace("No-op", entries: entries), "No-op")
    }

    func testLeadingReplacementPreservesExplicitCapitalization() {
        let entries = [DictionaryEntry(phrase: "the", aliases: ["teh", "the"])]
        let result = DictionaryReplacer.apply("  \"teh answer\"", entries: entries)
        XCTAssertEqual(result.text, "  \"the answer\"")
        XCTAssertTrue(result.preservesLeadingCapitalization)

        let unchangedSpelling = DictionaryReplacer.apply("the answer", entries: entries)
        XCTAssertEqual(unchangedSpelling.text, "the answer")
        XCTAssertTrue(unchangedSpelling.preservesLeadingCapitalization)
    }

    func testLaterReplacementDoesNotChangeLeadingCapitalizationPolicy() {
        let entries = [DictionaryEntry(phrase: "the", aliases: ["teh"])]
        let result = DictionaryReplacer.apply("Meet teh team", entries: entries)
        XCTAssertEqual(result.text, "Meet the team")
        XCTAssertFalse(result.preservesLeadingCapitalization)
    }

    func testReplacementWithoutLettersDoesNotPreserveLeadingCapitalization() {
        let entries = [DictionaryEntry(phrase: "…", aliases: ["um"])]
        let result = DictionaryReplacer.apply("um hello", entries: entries)
        XCTAssertEqual(result.text, "… hello")
        XCTAssertFalse(result.preservesLeadingCapitalization)
    }
}
