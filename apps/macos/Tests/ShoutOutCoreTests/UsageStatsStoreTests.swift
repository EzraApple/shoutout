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
        XCTAssertEqual(store.recentSessions.map(\.date), [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 1),
        ])
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

    func testPersistsPerformanceMetrics() throws {
        let fileURL = temporaryFileURL()
        let store = UsageStatsStore(fileURL: fileURL)
        let performance = UsagePerformanceMetrics(
            inputMode: "hold",
            pressToRecordStartMs: 42,
            pressToCommitMs: 300,
            recordStartRequestToReadyMs: 12,
            stopToSamplesMs: 8,
            stopToPasteMs: 640,
            queueWaitMs: 0,
            transcriptionWallMs: 520,
            recordingMs: 2_000,
            modelWaitMs: 0,
            whisperWallMs: 500,
            postProcessMs: 2,
            firstTokenMs: 120,
            whisperPipelineMs: 480,
            realTimeFactor: 0.25,
            speedFactor: 4.0,
            tokensPerSecond: 28.0,
            fallbackCount: 0
        )

        try store.record(finalText: "saved words", duration: 2, model: "base", performance: performance)

        let reloadedStore = UsageStatsStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.recentSessions.first?.performance, performance)
        XCTAssertEqual(reloadedStore.allTimeSummary.averagePressToRecordStartMs, 42)
        XCTAssertEqual(reloadedStore.allTimeSummary.averageStopToPasteMs, 640)
        XCTAssertEqual(reloadedStore.allTimeSummary.averageRealTimeFactor, 0.25)
    }

    func testIgnoresBlankFinalText() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "   ", duration: 10, date: Date(), model: "base")
        XCTAssertEqual(store.allTimeSummary.sessionCount, 0)
    }

    func testDoesNotPersistDictatedText() throws {
        let fileURL = temporaryFileURL()
        let store = UsageStatsStore(fileURL: fileURL)

        try store.record(finalText: "private dictated words", duration: 10, date: Date(), model: "base")

        let savedJSON = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(savedJSON.contains("private dictated words"))
        XCTAssertFalse(savedJSON.contains("finalText"))
    }

    func testCachesDailyInsightSummaries() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        try store.record(finalText: "one two three", duration: 30, date: yesterday, model: "base")
        try store.record(finalText: "four five", duration: 30, date: today, model: "base")

        XCTAssertEqual(store.insights.days.count, 2)
        XCTAssertEqual(store.insights.days.map(\.wordCount), [3, 2])
        XCTAssertEqual(store.insights.currentStreakDays, 2)
        XCTAssertEqual(store.insights.longestStreakDays, 2)
        XCTAssertEqual(store.insights.bestDayWordCount, 3)
        XCTAssertEqual(store.insights.averageWordsPerActiveDay, 3)
    }

    func testClearRefreshesCachedInsights() throws {
        let store = UsageStatsStore(fileURL: temporaryFileURL())
        try store.record(finalText: "one two", duration: 10, date: Date(), model: "base")

        try store.clear()

        XCTAssertEqual(store.insights, .empty)
        XCTAssertEqual(store.todaySummary, .empty)
        XCTAssertEqual(store.allTimeSummary, .empty)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
