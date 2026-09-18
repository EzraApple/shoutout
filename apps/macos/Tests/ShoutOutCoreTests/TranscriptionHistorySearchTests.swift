import XCTest
@testable import ShoutOutCore

final class TranscriptionHistorySearchTests: XCTestCase {
    private func entry(_ text: String) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(date: Date(), text: text, wordCount: 1, duration: 1, model: "test")
    }

    func testBlankQueryAndChronologicalOrder() throws {
        let entries = [entry("Notes from today"), entry("Notes from yesterday")]
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: " \n"), entries)
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: "notes"), entries)
    }

    func testCaseAccentsPartialWordsAndMultipleTerms() throws {
        let entries = [entry("Meet at the café after lunch"), entry("Lunch notes")]
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: "CAFÉ lun"), [entries[0]])
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: "cafe"), [entries[0]])
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: "lunch meet"), [entries[0]])
    }

    func testCommonTypos() throws {
        let entries = [entry("Review the project notes")]
        for query in ["projet", "projeect", "projevt", "proejct"] {
            XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: query), entries, query)
        }
    }

    func testAvoidsSemanticAndOverlyLooseMatches() throws {
        let entries = [entry("Send the project notes")]
        for query in ["email", "cat", "xrojectz", "project tomorrow"] {
            XCTAssertTrue(try TranscriptionHistorySearch.search(entries, query: query).isEmpty, query)
        }
    }

    func testSearchesVisibleTextOnly() throws {
        var transcript = entry("The final transcript")
        transcript.languagePassCandidate = "unrelated rejected candidate"
        XCTAssertTrue(try TranscriptionHistorySearch.search([transcript], query: "rejected").isEmpty)
    }

    func testFindsEntriesBeyondFirstPage() throws {
        let entries = (0..<200).map { entry("Recording number \($0)") }
        XCTAssertEqual(try TranscriptionHistorySearch.search(entries, query: "199"), [entries[199]])
    }
}
