import Foundation
import XCTest
@testable import ShoutOutCore

final class UsageInsightsReportTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSparseWeekFillsCalendarDaysAndSeparatesPreviousPeriod() {
        let now = date(2026, 10, 26, 12)
        let report = UsageInsightsReport(sessions: [
            session(2026, 10, 13, words: 1),
            session(2026, 10, 19, words: 2),
            session(2026, 10, 20, words: 3),
            session(2026, 10, 26, words: 4),
        ], range: .week, now: now, calendar: utc)

        XCTAssertEqual(report.periodStart, date(2026, 10, 20))
        XCTAssertEqual(report.periodEnd, now)
        XCTAssertEqual(report.buckets.map(\.wordCount), [3, 0, 0, 0, 0, 0, 4])
        XCTAssertEqual(report.buckets.map(\.sessionCount), [1, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(report.buckets.filter(\.isCurrent).map(\.start), [date(2026, 10, 26)])
        XCTAssertEqual(report.summary.wordCount, 7)
        XCTAssertEqual(report.previousSummary?.wordCount, 3)
    }

    func testThirtyDaysUsesCalendarDayBoundariesAndEmptyBaseline() {
        let report = UsageInsightsReport(sessions: [
            session(2026, 9, 26, words: 100),
            session(2026, 9, 27, words: 7),
        ], range: .month, now: date(2026, 10, 26, 12), calendar: utc)

        XCTAssertEqual(report.periodStart, date(2026, 9, 27))
        XCTAssertEqual(report.buckets.count, 30)
        XCTAssertEqual(report.buckets.first?.wordCount, 7)
        XCTAssertEqual(report.previousSummary?.wordCount, 100)

        let empty = UsageInsightsReport(sessions: [], range: .month, now: date(2026, 10, 26), calendar: utc)
        XCTAssertEqual(empty.previousSummary?.wordCount, 0)
        XCTAssertNil(empty.previousSummary?.averageWordsPerMinute)
    }

    func testPaceIsWeightedByDurationAndInvalidSessionsAreExcluded() {
        let now = date(2026, 10, 26, 12)
        let report = UsageInsightsReport(sessions: [
            session(2026, 10, 26, words: 60, duration: 60),
            session(2026, 10, 26, words: 20, duration: 120),
            session(2026, 10, 26, words: 5, duration: 0),
            session(2026, 10, 26, words: -5),
            session(2026, 10, 26, words: 9, duration: .nan),
            session(2026, 10, 27, words: 10),
        ], range: .week, now: now, calendar: utc)

        XCTAssertEqual(report.summary.sessionCount, 2)
        XCTAssertEqual(report.summary.wordCount, 80)
        XCTAssertEqual(report.summary.totalDuration, 180)
        XCTAssertEqual(report.summary.averageWordsPerMinute, 27)
        XCTAssertEqual(report.buckets.last?.wordCount, 80)
    }

    func testZeroWordsRemainAValidSessionWithZeroPace() {
        let report = UsageInsightsReport(sessions: [session(2026, 10, 26, words: 0)],
                                         range: .week, now: date(2026, 10, 26, 12), calendar: utc)
        XCTAssertEqual(report.summary.sessionCount, 1)
        XCTAssertEqual(report.summary.averageWordsPerMinute, 0)
    }

    func testExtremeCountsSaturateWithoutOverflow() {
        let report = UsageInsightsReport(sessions: [
            session(2026, 10, 26, words: Int.max, duration: 1),
            session(2026, 10, 26, words: Int.max, duration: 1),
        ], range: .week, now: date(2026, 10, 26, 12), calendar: utc)

        XCTAssertEqual(report.summary.wordCount, Int.max)
        XCTAssertEqual(report.buckets.last?.wordCount, Int.max)
        XCTAssertEqual(report.summary.averageWordsPerMinute, Int.max)
    }

    func testDayBucketsFollowLocalDSTBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let report = UsageInsightsReport(sessions: [], range: .week, now: now, calendar: calendar)
        let march8 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let bucket = report.buckets.first { $0.start == march8 }!

        XCTAssertEqual(bucket.end.timeIntervalSince(bucket.start), 23 * 60 * 60)
        XCTAssertEqual(report.buckets.count, 7)
    }

    func testAllTimeKeepsShortHistoryDailyAndIncludesNowOnABoundary() {
        let now = date(2026, 10, 26)
        let sessions = [session(2026, 10, 24, words: 9), session(2026, 10, 26, hour: 0, words: 3)]
        let report = UsageInsightsReport(sessions: sessions, range: .allTime, now: now, calendar: utc)

        XCTAssertEqual(report.buckets.map(\.wordCount), [9, 0, 3])
        XCTAssertEqual(report.activityTrend, [9, 4.5, 4])
        XCTAssertEqual(report.buckets.last?.end, date(2026, 10, 27))
        XCTAssertNil(report.previousSummary)
    }

    func testMultiYearAllTimeStaysCompactAndPreservesCountsAndCalendarCoverage() throws {
        let now = date(2027, 1, 1)
        for year in [2022, 2017] {
            let sessions = [
                session(year, 5, 2, words: 25),
                session(2025, 1, 1, words: 35),
                session(2027, 1, 1, hour: 0, words: 5),
            ]
            let report = UsageInsightsReport(sessions: sessions, range: .allTime, now: now, calendar: utc)
            let buckets = report.buckets
            let latest = try XCTUnwrap(buckets.last)
            XCTAssertTrue((10...32).contains(buckets.count))
            XCTAssertEqual(buckets.first?.start, date(year, 5, 2))
            XCTAssertEqual(latest.end, date(2027, 1, 2))
            XCTAssertTrue(latest.isCurrent)
            XCTAssertEqual(latest.wordsPerDay, 5)
            XCTAssertTrue(zip(buckets, buckets.dropFirst()).allSatisfy { $0.end == $1.start })
            XCTAssertTrue(buckets.contains { $0.wordCount == 0 })
            XCTAssertEqual(buckets.map(\.wordCount).reduce(0, +), report.summary.wordCount)
            XCTAssertEqual(buckets.map(\.sessionCount).reduce(0, +), sessions.count)

            let trailing = buckets.suffix(3)
            let days = trailing.map(\.dayCount).reduce(0, +)
            let words = trailing.map(\.wordCount).reduce(0, +)
            XCTAssertEqual(report.activityTrend.count, buckets.count)
            XCTAssertEqual(try XCTUnwrap(report.activityTrend.last), Double(words) / Double(days), accuracy: 0.001)
        }
    }

    func testRhythmNeedsTenSessionsAcrossFiveDistinctDays() {
        let now = date(2026, 10, 26, 23)
        let nine = (0..<9).map { index in
            session(2026, 10, 20 + index / 2, words: index + 1)
        }
        let below = UsageInsightsReport(sessions: nine, range: .week, now: now, calendar: utc)
        XCTAssertNil(below.medianDuration)
        XCTAssertNil(below.mostActiveWeekday)
        XCTAssertNil(below.mostActiveDayPart)

        let tenOneDay = UsageInsightsReport(sessions: Array(repeating: session(2026, 10, 26), count: 10),
                                            range: .week, now: now, calendar: utc)
        XCTAssertNil(tenOneDay.medianWordCount)
    }

    func testEvenMediansAndMostRecentCategoryBreakTies() {
        let now = date(2026, 10, 26, 23)
        let sessions = (0..<5).flatMap { index in
            [session(2026, 10, 20 + index, hour: 8, words: 1, duration: 2),
             session(2026, 10, 20 + index, hour: 18, words: 4, duration: 8)]
        }
        let report = UsageInsightsReport(sessions: sessions, range: .week, now: now, calendar: utc)

        XCTAssertEqual(report.medianDuration, 5)
        XCTAssertEqual(report.medianWordCount, 2.5)
        XCTAssertEqual(report.mostActiveDayPart, .evening)
        XCTAssertEqual(report.mostActiveWeekday, 7) // Saturday is the most recent tied weekday.
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func session(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10,
                         words: Int = 1, duration: TimeInterval = 60) -> UsageStatsSession {
        UsageStatsSession(date: date(year, month, day, hour), duration: duration, model: "test",
                          wordCount: words, wordsPerMinute: 0)
    }
}
