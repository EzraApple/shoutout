import XCTest
@testable import ShoutOutCore

final class TranscriptionHistoryStoreTests: XCTestCase {
    func testEmptyHistoryStartsEmpty() {
        let store = TranscriptionHistoryStore(fileURL: temporaryFileURL())
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(store.recentEntries.isEmpty)
    }

    func testRecordsAndPersistsTranscriptText() throws {
        let fileURL = temporaryFileURL()
        let store = TranscriptionHistoryStore(fileURL: fileURL)

        try store.record(
            text: "hello from history",
            duration: 2.4,
            date: Date(timeIntervalSince1970: 10),
            model: "large"
        )

        let reloadedStore = TranscriptionHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.recentEntries.first?.text, "hello from history")
        XCTAssertEqual(reloadedStore.recentEntries.first?.wordCount, 3)
        XCTAssertEqual(reloadedStore.recentEntries.first?.duration, 2.4)
        XCTAssertEqual(reloadedStore.recentEntries.first?.model, "large")
    }

    func testRecordsAndPersistsLanguagePassDetails() throws {
        let fileURL = temporaryFileURL()
        let store = TranscriptionHistoryStore(fileURL: fileURL)

        try store.record(
            text: "Does this PR also make it actually register manage tabs?",
            duration: 2.4,
            date: Date(timeIntervalSince1970: 10),
            model: "large",
            languagePassInput: "Does this PR also make it a... actually register manage tabs?",
            languagePassCandidate: "Does this PR also make it a... actually register manage tabs?",
            languagePassOutput: "Does this PR also make it actually register manage tabs?",
            languagePassAccepted: true,
            languagePassFallbackReason: nil
        )

        let entry = try XCTUnwrap(TranscriptionHistoryStore(fileURL: fileURL).recentEntries.first)
        XCTAssertEqual(
            entry.languagePassInput,
            "Does this PR also make it a... actually register manage tabs?"
        )
        XCTAssertEqual(
            entry.languagePassCandidate,
            "Does this PR also make it a... actually register manage tabs?"
        )
        XCTAssertEqual(
            entry.languagePassOutput,
            "Does this PR also make it actually register manage tabs?"
        )
        XCTAssertEqual(entry.languagePassAccepted, true)
        XCTAssertTrue(entry.hasLanguagePassDetails)
    }

    func testIgnoresBlankTranscriptText() throws {
        let store = TranscriptionHistoryStore(fileURL: temporaryFileURL())

        try store.record(text: "   ", duration: 2, model: "large")

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRecentEntriesNewestFirst() throws {
        let store = TranscriptionHistoryStore(fileURL: temporaryFileURL())

        try store.record(text: "old", duration: 1, date: Date(timeIntervalSince1970: 1), model: "base")
        try store.record(text: "new", duration: 1, date: Date(timeIntervalSince1970: 2), model: "base")

        XCTAssertEqual(store.recentEntries.map(\.text), ["new", "old"])
    }

    func testCapsStoredEntries() throws {
        let fileURL = temporaryFileURL()
        let store = TranscriptionHistoryStore(fileURL: fileURL, maxEntries: 2)

        try store.record(text: "one", duration: 1, date: Date(timeIntervalSince1970: 1), model: "base")
        try store.record(text: "two", duration: 1, date: Date(timeIntervalSince1970: 2), model: "base")
        try store.record(text: "three", duration: 1, date: Date(timeIntervalSince1970: 3), model: "base")

        XCTAssertEqual(store.recentEntries.map(\.text), ["three", "two"])

        let reloadedStore = TranscriptionHistoryStore(fileURL: fileURL, maxEntries: 2)
        XCTAssertEqual(reloadedStore.recentEntries.map(\.text), ["three", "two"])
    }

    func testClearRemovesHistory() throws {
        let store = TranscriptionHistoryStore(fileURL: temporaryFileURL())

        try store.record(text: "saved", duration: 1, model: "base")
        try store.clear()

        XCTAssertTrue(store.entries.isEmpty)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
