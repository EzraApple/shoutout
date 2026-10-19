import XCTest
@testable import ShoutOutCore

final class DictionaryStoreTests: XCTestCase {
    func testStartsEmptyAndUsesBackwardCompatiblePath() {
        let store = DictionaryStore(fileURL: temporaryFileURL())
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(
            DictionaryStore.defaultFileURL(bundleIdentifier: "com.ezraapple.shoutout").lastPathComponent,
            "dictionary.json"
        )
    }

    func testAddEditDeleteAndReloadPreserveIdentity() throws {
        let fileURL = temporaryFileURL()
        let store = DictionaryStore(fileURL: fileURL)
        try store.addEntry(phrase: "  ShoutOut  ", aliasesText: " shout out, SHOUT OUT\n shoutout ")
        let original = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(original.phrase, "ShoutOut")
        XCTAssertEqual(original.aliases, ["shout out", "shoutout"])

        try store.updateEntry(id: original.id, phrase: " ShoutOut App ", aliasesText: " shout out app ")
        let reloaded = DictionaryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries[0].id, original.id)
        XCTAssertEqual(reloaded.entries[0].phrase, "ShoutOut App")
        XCTAssertEqual(reloaded.entries[0].aliases, ["shout out app"])

        try store.deleteEntry(id: original.id)
        XCTAssertTrue(DictionaryStore(fileURL: fileURL).entries.isEmpty)
        XCTAssertThrowsError(try store.deleteEntry(id: original.id)) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .missingEntry)
        }
    }

    func testRejectsBlankPhraseAndAliases() throws {
        let store = DictionaryStore(fileURL: temporaryFileURL())
        XCTAssertThrowsError(try store.addEntry(phrase: "  ", aliasesText: "yes")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .emptyPhrase)
        }
        XCTAssertThrowsError(try store.addEntry(phrase: "Name", aliasesText: " , \n  ")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .emptyAliases)
        }
        try store.addEntry(phrase: "Name", aliasesText: "word")
        let id = try XCTUnwrap(store.entries.first?.id)
        XCTAssertThrowsError(try store.updateEntry(id: id, phrase: "Name", aliasesText: " , ")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .emptyAliases)
        }
        XCTAssertEqual(store.entries[0].aliases, ["word"])
    }

    func testRejectsDuplicatePhraseAndAliasAcrossEntries() throws {
        let store = DictionaryStore(fileURL: temporaryFileURL())
        try store.addEntry(phrase: "Alpha", aliasesText: "one")
        try store.addEntry(phrase: "Beta", aliasesText: "two")
        let betaID = try XCTUnwrap(store.entries.last?.id)
        XCTAssertThrowsError(try store.addEntry(phrase: "ALPHA", aliasesText: "different")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .duplicatePhrase("ALPHA"))
        }
        XCTAssertThrowsError(try store.addEntry(phrase: "Gamma", aliasesText: "ONE")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .conflictingAlias("ONE"))
        }
        XCTAssertThrowsError(try store.updateEntry(id: betaID, phrase: "Alpha", aliasesText: "two")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .duplicatePhrase("Alpha"))
        }
        XCTAssertThrowsError(try store.updateEntry(id: betaID, phrase: "Beta", aliasesText: "One")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .conflictingAlias("One"))
        }
        try store.updateEntry(id: betaID, phrase: "Beta", aliasesText: "two, TWO")
        XCTAssertEqual(store.entries.last?.aliases, ["two"])
    }

    func testLoadsLegacyEntryWithEmptyAliases() throws {
        let fileURL = temporaryFileURL()
        let id = UUID()
        let legacy = """
        [{"id":"\(id.uuidString)","phrase":"Legacy","aliases":[]}]
        """
        try legacy.write(to: fileURL, atomically: true, encoding: .utf8)
        let store = DictionaryStore(fileURL: fileURL)
        XCTAssertEqual(store.entries, [DictionaryEntry(id: id, phrase: "Legacy", aliases: [])])
    }

    func testInvalidExistingFileBlocksEveryMutationWithoutOverwritingIt() throws {
        let fileURL = temporaryFileURL()
        let invalidData = Data("{ not valid JSON".utf8)
        try invalidData.write(to: fileURL)
        let knownEntry = DictionaryEntry(phrase: "Known", aliases: ["known"])
        let store = DictionaryStore(fileURL: fileURL, defaultEntries: [knownEntry])

        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.entries, [knownEntry])
        XCTAssertThrowsError(try store.addEntry(phrase: "New", aliasesText: "new")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .loadFailed)
        }
        XCTAssertThrowsError(try store.updateEntry(id: knownEntry.id, phrase: "Updated", aliasesText: "updated")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .loadFailed)
        }
        XCTAssertThrowsError(try store.deleteEntry(id: knownEntry.id)) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .loadFailed)
        }
        XCTAssertEqual(store.entries, [knownEntry])
        XCTAssertEqual(try Data(contentsOf: fileURL), invalidData)
    }

    func testUnreadableFileSurfacesLoadError() throws {
        let fileURL = temporaryFileURL()
        try "[]".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let store = DictionaryStore(fileURL: fileURL)
        XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.loadError?.contains("Could not read") == true)
        XCTAssertThrowsError(try store.addEntry(phrase: "New", aliasesText: "new")) { error in
            XCTAssertEqual(error as? DictionaryStoreError, .loadFailed)
        }
    }

    func testRepairAndReloadRetainLastKnownEntriesUntilSuccess() throws {
        let fileURL = temporaryFileURL()
        let store = DictionaryStore(fileURL: fileURL)
        try store.addEntry(phrase: "Before", aliasesText: "before")
        let originalEntries = store.entries

        try "broken".write(to: fileURL, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.entries, originalEntries)
        XCTAssertThrowsError(try store.addEntry(phrase: "Blocked", aliasesText: "blocked"))

        let repairedData = try JSONEncoder().encode(originalEntries)
        try repairedData.write(to: fileURL, options: .atomic)
        store.reload()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.entries, originalEntries)
        try store.addEntry(phrase: "After", aliasesText: "after")
        XCTAssertEqual(DictionaryStore(fileURL: fileURL).entries.count, 2)
    }

    func testFailedSaveKeepsMemoryAndExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("dictionary.json")
        let store = DictionaryStore(fileURL: fileURL)
        try store.addEntry(phrase: "Original", aliasesText: "original")
        let originalEntries = store.entries
        let originalData = try Data(contentsOf: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        XCTAssertThrowsError(try store.addEntry(phrase: "Later", aliasesText: "later"))
        XCTAssertEqual(store.entries, originalEntries)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
