import XCTest
@testable import ShoutOutCore

final class UsageStatsStoreTests: XCTestCase {
    func testEmptySummaryIsZeroed() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        XCTAssertEqual(store.allTimeSummary.sessionCount, 0)
        XCTAssertEqual(store.allTimeSummary.wordCount, 0)
        XCTAssertEqual(store.allTimeSummary.averageWordsPerMinute, 0)
    }

    func testRecordsSessionCount() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "hello world", duration: 10, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.sessionCount, 1)
    }

    func testCountsWords() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "hello, world again", duration: 10, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.wordCount, 3)
    }

    func testCalculatesWordsPerMinute() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "one two three four", duration: 30, date: Date(), model: "base")
        XCTAssertEqual(store.recentSessions.first?.wordsPerMinute, 8)
    }

    func testClampsTinyDurationsForWordsPerMinute() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "one two", duration: 0, date: Date(), model: "base")
        XCTAssertGreaterThan(store.recentSessions.first?.wordsPerMinute ?? 0, 0)
    }

    func testTodaySummaryFiltersOldEntries() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "today words", duration: 10, date: Date(), model: "base")
        try store.record(finalText: "old words", duration: 10, date: Date(timeIntervalSinceNow: -172_800), model: "base")
        XCTAssertEqual(store.todaySummary.sessionCount, 1)
        XCTAssertEqual(store.todaySummary.wordCount, 2)
    }

    func testAllTimeSummaryIncludesOldEntries() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "today words", duration: 10, date: Date(), model: "base")
        try store.record(finalText: "old words", duration: 10, date: Date(timeIntervalSinceNow: -172_800), model: "base")
        XCTAssertEqual(store.allTimeSummary.sessionCount, 2)
        XCTAssertEqual(store.allTimeSummary.wordCount, 4)
    }

    func testPersistsStatsToDisk() throws {
        let fileURL = temporaryFileURL()
        let store = UsageStatsStore(fileURL: fileURL)
        try store.record(finalText: "saved words", duration: 15, date: Date(timeIntervalSince1970: 1_000), model: "small")

        let reloadedStore = UsageStatsStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.allTimeSummary.wordCount, 2)
        XCTAssertEqual(reloadedStore.recentSessions.first?.model, "small")
    }

    func testClearRemovesHistory() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "saved words", duration: 15, date: Date(), model: "small")
        try store.clear()
        XCTAssertEqual(store.allTimeSummary.sessionCount, 0)
    }

    func testRecentSessionsNewestFirst() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "old", duration: 10, date: Date(timeIntervalSince1970: 1), model: "base")
        try store.record(finalText: "new", duration: 10, date: Date(timeIntervalSince1970: 2), model: "base")
        XCTAssertEqual(store.recentSessions.map(\.finalText), ["new", "old"])
    }

    func testAverageWordsPerMinuteUsesTotalDuration() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "one two", duration: 60, date: Date(), model: "base")
        try store.record(finalText: "three four", duration: 60, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.averageWordsPerMinute, 2)
    }

    func testPunctuationDoesNotInflateWordCount() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "hello, world! are-you-ready?", duration: 10, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.wordCount, 3)
    }

    func testTracksTotalDuration() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "one", duration: 1.25, date: Date(), model: "base")
        try store.record(finalText: "two", duration: 2.75, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.totalDuration, 4.0)
    }

    func testIgnoresBlankFinalText() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "   ", duration: 10, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.sessionCount, 0)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
