import XCTest
@testable import ShoutOutCore

final class DictionaryStoreTests: XCTestCase {
    func testLoadsDefaultEntriesWhenFileIsMissing() throws {
        let store = try makeStore()
        XCTAssertTrue(store.entries.contains { $0.phrase == "Yuxin" })
    }

    func testAddsEntryWithTrimmedPhrase() throws {
        let store = try makeStore()
        try store.addEntry(phrase: "  Linear  ", aliasesText: "line ear")
        XCTAssertTrue(store.entries.contains { $0.phrase == "Linear" })
    }

    func testSplitsAliasesByCommaAndNewline() throws {
        let store = try makeStore()
        try store.addEntry(phrase: "Yuxin", aliasesText: "you shin, yu xin\nyoo shin")
        let entry = try XCTUnwrap(store.entries.first { $0.phrase == "Yuxin" })
        XCTAssertEqual(entry.aliases, ["you shin", "yu xin", "yoo shin"])
    }

    func testIgnoresBlankAliases() throws {
        let store = try makeStore()
        try store.addEntry(phrase: "Replo", aliasesText: "rep low,, \n reply low")
        let entry = try XCTUnwrap(store.entries.first { $0.phrase == "Replo" })
        XCTAssertEqual(entry.aliases, ["rep low", "reply low"])
    }

    func testRejectsEmptyPhrase() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.addEntry(phrase: "   ", aliasesText: "empty"))
    }

    func testPersistsEntriesToDisk() throws {
        let fileURL = temporaryFileURL()
        let store = DictionaryStore(fileURL: fileURL, defaultEntries: [])
        try store.addEntry(phrase: "Shout Out", aliasesText: "shoutout")

        let reloadedStore = DictionaryStore(fileURL: fileURL, defaultEntries: [])
        XCTAssertEqual(reloadedStore.entries, [DictionaryEntry(phrase: "Shout Out", aliases: ["shoutout"])])
    }

    func testDeletesEntry() throws {
        let store = try makeStore()
        try store.addEntry(phrase: "Linear", aliasesText: "line ear")
        let id = try XCTUnwrap(store.entries.first { $0.phrase == "Linear" }?.id)

        try store.deleteEntry(id: id)
        XCTAssertFalse(store.entries.contains { $0.phrase == "Linear" })
    }

    func testUpdatesEntry() throws {
        let store = try makeStore()
        try store.addEntry(phrase: "Linear", aliasesText: "line ear")
        let id = try XCTUnwrap(store.entries.first { $0.phrase == "Linear" }?.id)

        try store.updateEntry(id: id, phrase: "Linear App", aliasesText: "linear")
        XCTAssertTrue(store.entries.contains { $0.phrase == "Linear App" && $0.aliases == ["linear"] })
    }

    func testCorruptFileFallsBackToDefaults() throws {
        let fileURL = temporaryFileURL()
        try "{ nope".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = DictionaryStore(fileURL: fileURL, defaultEntries: [.init(phrase: "Fallback", aliases: [])])
        XCTAssertEqual(store.entries, [.init(phrase: "Fallback", aliases: [])])
    }

    private func makeStore() throws -> DictionaryStore {
        DictionaryStore(fileURL: temporaryFileURL(), defaultEntries: DictionaryEntry.defaultEntries)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
