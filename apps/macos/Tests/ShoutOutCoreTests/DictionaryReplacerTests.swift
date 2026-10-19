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

    func testCasualCleanupAcceptsLowercaseDictionaryWords() throws {
        let entries = [DictionaryEntry(phrase: "Replo", aliases: ["rep low"])]
        let correctedText = DictionaryReplacer.replace("open rep low", entries: entries)
        XCTAssertEqual(correctedText, "open Replo")

        let validation = LanguagePassValidator.validate(candidate: "open replo", baseText: correctedText)
        let acceptedText = try XCTUnwrap(validation.acceptedText)
        let formatted = LanguagePassOutputFormatter.format(
            source: correctedText, finalText: acceptedText, style: .casual,
            enabled: true, fallbackReason: nil
        )
        XCTAssertEqual(formatted.text, "open replo")
    }

    func testDisabledCleanupKeepsDictionaryReplacement() {
        let entries = [DictionaryEntry(phrase: "Replo", aliases: ["rep low"])]
        let correctedText = DictionaryReplacer.replace("open rep low", entries: entries)
        let formatted = LanguagePassOutputFormatter.format(
            source: correctedText, finalText: correctedText, style: .casual,
            enabled: false, fallbackReason: "disabled"
        )
        XCTAssertEqual(formatted.text, "open Replo")
    }
}
