// MARK: - CCUsageFetcherTests.swift
// Verifies CCUsageFetcher weekly and daily aggregation across different locales and calendar settings,
// specifically guarding against regressions where Monday-first calendars caused weekly usage to report 0 (Issue #27).

import XCTest
@testable import AgentLimits

final class CCUsageFetcherTests: XCTestCase {
    private let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Week Start Calculation Tests

    func testCalculateWeekStartWithSundayFirstCalendar() {
        // 2026-10-30 is a Friday.
        let now = isoDateFormatter.date(from: "2026-10-30 12:00:00")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1 // Sunday

        let weekStart = CCUsageFetcher.calculateWeekStart(from: now, calendar: calendar)

        let expected = isoDateFormatter.date(from: "2026-10-25 00:00:00")!
        XCTAssertEqual(weekStart, expected)
    }

    func testCalculateWeekStartWithMondayFirstCalendar() {
        // 2026-10-30 is a Friday.
        // In Monday-first calendars (firstWeekday == 2), Sunday would incorrectly be considered
        // the end of the week (2026-11-01) if firstWeekday is not explicitly overridden.
        let now = isoDateFormatter.date(from: "2026-10-30 12:00:00")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2 // Monday

        let weekStart = CCUsageFetcher.calculateWeekStart(from: now, calendar: calendar)

        // Must still return the Sunday at the beginning of the week (2026-10-25), not the upcoming Sunday (2026-11-01).
        let expected = isoDateFormatter.date(from: "2026-10-25 00:00:00")!
        XCTAssertEqual(weekStart, expected)
    }

    // MARK: - Issue #27 Regression Test (Codex response with Monday-first calendar)

    func testParseCodexResponseCalculatesWeeklyCorrectlyRegardlessOfFirstWeekday() throws {
        // Payload from Issue #27 (dates 2026-10-23 through 2026-10-30)
        let jsonString = """
        {
          "daily": [
            { "cacheCreationTokens": 0, "cacheReadTokens": 11566720, "costUSD": 2.26992958, "date": "2026-10-23", "inputTokens": 879520, "outputTokens": 46979, "reasoningOutputTokens": 13813, "totalTokens": 12493219 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 129598336, "costUSD": 26.944086960000003, "date": "2026-10-24", "inputTokens": 3758796, "outputTokens": 312331, "reasoningOutputTokens": 131229, "totalTokens": 133669463 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 25265792, "costUSD": 4.0421695, "date": "2026-10-25", "inputTokens": 699487, "outputTokens": 39846, "reasoningOutputTokens": 12346, "totalTokens": 26005125 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 178293376, "costUSD": 31.670253020000004, "date": "2026-10-26", "inputTokens": 5187817, "outputTokens": 381423, "reasoningOutputTokens": 153449, "totalTokens": 183862616 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 122553984, "costUSD": 25.312786399999997, "date": "2026-10-27", "inputTokens": 2205911, "outputTokens": 236439, "reasoningOutputTokens": 115244, "totalTokens": 124996334 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 5145344, "costUSD": 1.1890498999999999, "date": "2026-10-28", "inputTokens": 315438, "outputTokens": 24213, "reasoningOutputTokens": 7381, "totalTokens": 5484995 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 12104704, "costUSD": 1.91916558, "date": "2026-10-29", "inputTokens": 400494, "outputTokens": 19197, "reasoningOutputTokens": 11154, "totalTokens": 12524395 },
            { "cacheCreationTokens": 0, "cacheReadTokens": 0, "costUSD": 0.0022721, "date": "2026-10-30", "inputTokens": 22651, "outputTokens": 14, "reasoningOutputTokens": 0, "totalTokens": 22665 }
          ],
          "totals": {
            "cacheCreationTokens": 0,
            "cacheReadTokens": 484528256,
            "costUSD": 93.34971304,
            "inputTokens": 13470114,
            "outputTokens": 1060442,
            "reasoningOutputTokens": 444616,
            "totalTokens": 499058812
          }
        }
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let now = isoDateFormatter.date(from: "2026-10-30 18:00:00")!

        let fetcher = CCUsageFetcher()

        // 1. Test with Sunday-first calendar (e.g. en_US / ja_JP)
        var sundayFirstCalendar = Calendar(identifier: .gregorian)
        sundayFirstCalendar.timeZone = TimeZone(identifier: "UTC")!
        sundayFirstCalendar.locale = Locale(identifier: "en_US")
        sundayFirstCalendar.firstWeekday = 1

        let snapshotSunday = try fetcher.parseResponse(
            jsonData: data,
            provider: .codex,
            now: now,
            calendar: sundayFirstCalendar
        )

        // 2. Test with Monday-first calendar (e.g. en_GB / fr_FR / de_DE)
        var mondayFirstCalendar = Calendar(identifier: .gregorian)
        mondayFirstCalendar.timeZone = TimeZone(identifier: "UTC")!
        mondayFirstCalendar.locale = Locale(identifier: "en_GB")
        mondayFirstCalendar.firstWeekday = 2

        let snapshotMonday = try fetcher.parseResponse(
            jsonData: data,
            provider: .codex,
            now: now,
            calendar: mondayFirstCalendar
        )

        // Both calendars must yield the identical weekly period (2026-10-25 through 2026-10-30).
        // 10-25: 26,005,125 tokens, $4.0421695
        // 10-26: 183,862,616 tokens, $31.67025302
        // 10-27: 124,996,334 tokens, $25.3127864
        // 10-28: 5,484,995 tokens, $1.1890499
        // 10-29: 12,524,395 tokens, $1.91916558
        // 10-30: 22,665 tokens, $0.0022721
        // Total expected tokens: 352,896,130
        let expectedWeeklyTokens = 352896130
        let expectedWeeklyCost = 64.1356965

        XCTAssertEqual(snapshotSunday.thisWeek.totalTokens, expectedWeeklyTokens)
        XCTAssertEqual(snapshotMonday.thisWeek.totalTokens, expectedWeeklyTokens)
        XCTAssertEqual(snapshotMonday.thisWeek.costUSD, expectedWeeklyCost, accuracy: 0.0001)

        // Guard against regression: thisWeek tokens and cost must NOT be 0
        XCTAssertGreaterThan(snapshotMonday.thisWeek.totalTokens, 0)
        XCTAssertGreaterThan(snapshotMonday.thisWeek.costUSD, 0)
    }

    // MARK: - Claude Response Test

    func testParseClaudeResponseCalculatesWeeklyCorrectlyWithMondayFirstCalendar() throws {
        let jsonString = """
        {
          "daily": [
            { "date": "2026-10-24", "totalTokens": 1000, "totalCost": 1.0 },
            { "date": "2026-10-25", "totalTokens": 2000, "totalCost": 2.0 },
            { "date": "2026-10-26", "totalTokens": 3000, "totalCost": 3.0 }
          ],
          "totals": {
            "totalTokens": 6000,
            "totalCost": 6.0
          }
        }
        """
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let now = isoDateFormatter.date(from: "2026-10-26 12:00:00")!

        var mondayFirstCalendar = Calendar(identifier: .gregorian)
        mondayFirstCalendar.timeZone = TimeZone(identifier: "UTC")!
        mondayFirstCalendar.locale = Locale(identifier: "en_GB")
        mondayFirstCalendar.firstWeekday = 2

        let fetcher = CCUsageFetcher()
        let snapshot = try fetcher.parseResponse(
            jsonData: data,
            provider: .claude,
            now: now,
            calendar: mondayFirstCalendar
        )

        // Weekly should include 10-25 (Sun) and 10-26 (Mon), but not 10-24 (Sat)
        XCTAssertEqual(snapshot.thisWeek.totalTokens, 5000)
        XCTAssertEqual(snapshot.thisWeek.costUSD, 5.0, accuracy: 0.0001)
    }
}

