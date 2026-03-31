// MARK: - CopilotBillingFetcher.swift
// Fetches billing usage data from GitHub's usage_table API via WebView.
// Aggregates daily costs and premium request counts into TokenUsageSnapshot.

import Foundation
import WebKit

// MARK: - API Response Models

/// Response structure from GitHub billing usage_table API
struct CopilotBillingResponse: Decodable {
    let usage: [CopilotBillingEntry]
}

/// Single billing entry from usage_table API
struct CopilotBillingEntry: Decodable {
    let grossAmount: Double
    let quantity: Double
    let usageAt: String
    let sku: String
}

// MARK: - Error Types

/// Errors that can occur when fetching Copilot billing data
enum CopilotBillingFetcherError: LocalizedError {
    case scriptFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message):
            return "error.fetchFailed".localized(message)
        case .invalidResponse:
            return "error.parseFailed".localized()
        }
    }
}

// MARK: - Copilot Billing Fetcher

/// Fetches billing usage data from GitHub's usage_table API via WebView JavaScript.
/// Uses the same WebView session as CopilotUsageFetcher.
final class CopilotBillingFetcher {
    private let scriptRunner: WebViewScriptRunner

    init(scriptRunner: WebViewScriptRunner = WebViewScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    /// Fetches and aggregates billing data into a TokenUsageSnapshot.
    @MainActor
    func fetchBillingSnapshot(using webView: WKWebView) async throws -> TokenUsageSnapshot {
        let response: CopilotBillingResponse
        do {
            response = try await scriptRunner.decodeJSONScript(
                CopilotBillingResponse.self,
                script: Self.billingScript,
                webView: webView
            )
        } catch let error as WebViewScriptRunnerError {
            throw mapScriptError(error)
        }
        return buildSnapshot(from: response)
    }

    // MARK: - Snapshot Building

    /// Aggregates billing entries into today/thisWeek/thisMonth periods and daily entries.
    private func buildSnapshot(from response: CopilotBillingResponse) -> TokenUsageSnapshot {
        let calendar = Calendar.current
        let now = Date()

        // Filter to premium request entries only
        let premiumEntries = response.usage.filter { $0.sku == "copilot_premium_request" }

        // Group entries by local date
        let groupedByDate = groupEntriesByLocalDate(premiumEntries, calendar: calendar)

        // Calculate today's usage
        let todayKey = Self.dateKeyFormatter.string(from: now)
        let todayPeriod = aggregatePeriod(for: groupedByDate[todayKey] ?? [])

        // Calculate this week's usage (Sunday start)
        let weekStart = calculateWeekStart(from: now, calendar: calendar)
        let thisWeekPeriod = aggregateWeekPeriod(groupedByDate: groupedByDate, weekStart: weekStart, calendar: calendar)

        // Calculate this month's usage (all entries)
        let thisMonthPeriod = aggregatePeriod(for: premiumEntries)

        // Build daily usage entries for heatmap
        let dailyUsage = buildDailyUsage(from: groupedByDate)

        return TokenUsageSnapshot(
            provider: .copilot,
            fetchedAt: now,
            today: todayPeriod,
            thisWeek: thisWeekPeriod,
            thisMonth: thisMonthPeriod,
            dailyUsage: dailyUsage
        )
    }

    /// Groups billing entries by local date string (YYYY-MM-DD).
    private func groupEntriesByLocalDate(
        _ entries: [CopilotBillingEntry],
        calendar: Calendar
    ) -> [String: [CopilotBillingEntry]] {
        var grouped: [String: [CopilotBillingEntry]] = [:]
        for entry in entries {
            guard let date = Self.iso8601Formatter.date(from: entry.usageAt) else { continue }
            let key = Self.dateKeyFormatter.string(from: date)
            grouped[key, default: []].append(entry)
        }
        return grouped
    }

    /// Aggregates cost and quantity for a set of entries.
    private func aggregatePeriod(for entries: [CopilotBillingEntry]) -> TokenUsagePeriod {
        let totalCost = entries.reduce(0.0) { $0 + $1.grossAmount }
        let totalRequests = entries.reduce(0.0) { $0 + $1.quantity }
        return TokenUsagePeriod(costUSD: totalCost, totalTokens: Int(totalRequests))
    }

    /// Calculates start of the current week (Sunday).
    private func calculateWeekStart(from date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
    }

    /// Aggregates entries from week start (Sunday) through the current date.
    private func aggregateWeekPeriod(
        groupedByDate: [String: [CopilotBillingEntry]],
        weekStart: Date,
        calendar: Calendar
    ) -> TokenUsagePeriod {
        var totalCost = 0.0
        var totalRequests = 0.0
        let now = Date()

        var currentDate = weekStart
        while currentDate <= now {
            let key = Self.dateKeyFormatter.string(from: currentDate)
            if let entries = groupedByDate[key] {
                for entry in entries {
                    totalCost += entry.grossAmount
                    totalRequests += entry.quantity
                }
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        return TokenUsagePeriod(costUSD: totalCost, totalTokens: Int(totalRequests))
    }

    /// Builds sorted daily usage entries from grouped data for heatmap.
    private func buildDailyUsage(from groupedByDate: [String: [CopilotBillingEntry]]) -> [DailyUsageEntry] {
        groupedByDate.map { (dateKey, entries) in
            let totalRequests = entries.reduce(0.0) { $0 + $1.quantity }
            return DailyUsageEntry(date: dateKey, totalTokens: Int(totalRequests))
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Error Mapping

    private func mapScriptError(_ error: WebViewScriptRunnerError) -> CopilotBillingFetcherError {
        switch error {
        case .invalidResponse:
            return .invalidResponse
        case .scriptFailed(let message):
            return .scriptFailed(message)
        }
    }

    // MARK: - Date Formatters

    /// ISO8601 formatter for parsing `usageAt` timestamps
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Date formatter for local date keys (YYYY-MM-DD)
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - JavaScript Scripts

    /// Script to fetch billing data from GitHub usage_table API.
    /// Uses session cookies for authentication (credentials: "include").
    private static let billingScript = """
    return (async () => {
      try {
        const response = await fetch(
          "https://github.com/settings/billing/usage_table?group=0&period=3&product=&query=",
          {
            method: "GET",
            credentials: "include",
            headers: {
              "Accept": "application/json"
            }
          }
        );
        if (!response.ok) {
          throw new Error("HTTP " + response.status);
        }
        const data = await response.json();
        return JSON.stringify(data);
      } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return JSON.stringify({ "__error": message });
      }
    })();
    """
}
