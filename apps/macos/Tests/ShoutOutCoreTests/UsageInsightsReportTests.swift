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
        XCTAssertEqual(report.bucketUnit, .day)
        XCTAssertEqual(report.buckets.map(\.wordCount), [3, 0, 0, 0, 0, 0, 4])
        XCTAssertEqual(report.buckets.map(\.sessionCount), [1, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(report.buckets.filter(\.isCurrent).map(\.date), [date(2026, 10, 26)])
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

    func testAllTimeChangesBucketUnitAtCalendarThresholds() {
        let now = date(2026, 10, 26, 12)
        let daily = UsageInsightsReport(sessions: [session(2026, 9, 26)],
                                        range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(daily.bucketUnit, .day)
        XCTAssertEqual(daily.buckets.count, 31)
        XCTAssertNil(daily.previousSummary)

        let weekly = UsageInsightsReport(sessions: [session(2026, 9, 25)],
                                         range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(weekly.bucketUnit, .week)
        XCTAssertEqual(weekly.buckets.map(\.start), weekly.buckets.map { utc.dateInterval(of: .weekOfYear, for: $0.start)!.start })

        let monthly = UsageInsightsReport(sessions: [session(2026, 3, 1)],
                                          range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(monthly.bucketUnit, .month)
        XCTAssertEqual(monthly.buckets.count, 8)
        XCTAssertEqual(monthly.buckets.first?.start, date(2026, 3, 1))
        XCTAssertEqual(monthly.buckets.last?.start, date(2026, 10, 1))
    }

    func testWeekAndMonthBucketsCrossYearBoundaries() {
        let now = date(2027, 1, 4, 12)
        let weekly = UsageInsightsReport(sessions: [session(2026, 12, 1), session(2027, 1, 4)],
                                         range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(weekly.bucketUnit, .week)
        XCTAssertEqual(weekly.buckets.first?.start, date(2026, 11, 29))
        XCTAssertEqual(weekly.buckets.last?.start, date(2027, 1, 3))

        let month = UsageInsightsReport(sessions: [session(2026, 5, 1), session(2027, 1, 4)],
                                        range: .allTime, now: now, calendar: utc)
        XCTAssertEqual(month.bucketUnit, .month)
        XCTAssertEqual(month.buckets.count, 9)
        XCTAssertEqual(month.buckets.last?.start, date(2027, 1, 1))
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
