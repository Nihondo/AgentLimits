// MARK: - CCUsageFetcher.swift
// Executes ccusage CLI commands and parses JSON output to fetch token usage data.
// Uses ShellExecutor for command execution.

import Foundation

// MARK: - CLI Response Models

/// ccusage daily -j output format (Claude)
struct CCUsageClaudeResponse: Codable {
    struct DayEntry: Codable {
        let date: String           // "YYYY-MM-DD"
        let totalTokens: Int
        let totalCost: Double
    }
    struct Totals: Codable {
        let totalTokens: Int
        let totalCost: Double
    }
    let daily: [DayEntry]
    let totals: Totals
}

/// @ccusage/codex daily -j output format (Codex)
struct CCUsageCodexResponse: Codable {
    struct DayEntry: Codable {
        let date: String           // "Dec 14, 2025"
        let totalTokens: Int
        let costUSD: Double
    }
    struct Totals: Codable {
        let totalTokens: Int
        let costUSD: Double
    }
    let daily: [DayEntry]
    let totals: Totals
}

// MARK: - Errors

/// Errors that can occur during ccusage CLI execution
enum CCUsageFetcherError: Error, LocalizedError {
    case cliNotFound(command: String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timeout
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let command):
            return "CLI not found: \(command). Please install: npm install -g ccusage"
        case .executionFailed(let code, let stderr):
            return "CLI failed (\(code)): \(stderr)"
        case .timeout:
            return "CLI execution timed out"
        case .parseError(let message):
            return "Failed to parse JSON: \(message)"
        }
    }
}

// MARK: - CCUsage Fetcher

/// Executes ccusage CLI commands and parses the JSON output.
/// Uses ShellExecutor for command execution with timeout support.
final class CCUsageFetcher {
    private let shellExecutor: ShellExecutor
    private let settingsStore: CCUsageSettingsStore

    // MARK: - Date Formatters
    // Cached formatters to avoid repeated allocations during parsing operations.

    /// Formatter for ISO date strings (YYYY-MM-DD), used by Claude/ccusage responses
    private let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Formatter for English date strings (Dec 14, 2025), used by Codex/@ccusage responses
    private let englishFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Output formatter for ISO date strings (YYYY-MM-DD), used for today's date comparison
    private let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Creates a new fetcher with the specified configuration.
    /// - Parameters:
    ///   - timeout: Maximum time to wait for CLI completion (default: 60 seconds)
    ///   - settingsStore: Store for ccusage settings (default: shared instance)
    init(timeout: TimeInterval = 60, settingsStore: CCUsageSettingsStore = .shared) {
        self.shellExecutor = ShellExecutor(timeout: timeout)
        self.settingsStore = settingsStore
    }

    /// Fetches a token usage snapshot for the specified provider.
    /// - Parameter provider: The provider to fetch data for (Claude or Codex)
    /// - Returns: A snapshot containing today/week/month usage data
    /// - Throws: `CCUsageFetcherError` if CLI execution or parsing fails
    func fetchSnapshot(for provider: TokenUsageProvider) async throws -> TokenUsageSnapshot {
        // Load per-provider settings and build CLI command for this month.
        let settings = settingsStore.loadSettings()[provider] ?? .defaultSettings(for: provider)
        let startOfMonth = calculateStartOfMonth()
        let command = buildCommand(settings: settings, startDate: startOfMonth)
        // Execute CLI and parse JSON response into snapshot.
        let jsonData = try await executeCLI(command: command)
        return try parseResponse(jsonData: jsonData, provider: provider)
    }

    // MARK: - Private Methods

    /// Calculates the first day of the current month in YYYYMMDD format.
    /// Used as the start date parameter for CLI commands to fetch monthly usage.
    /// - Returns: Date string in compact format (e.g., "20251201" for December 1, 2025)
    private func calculateStartOfMonth() -> String {
        // Delegate to shared month-start resolver for consistency.
        MonthStartDateResolver.calculateStartOfMonthString()
    }

    /// Builds the full CLI command with arguments
    private func buildCommand(settings: CCUsageSettings, startDate: String) -> String {
        // Append start date and JSON output flag for consistent parsing.
        var cmd = settings.cliCommand
        cmd += " -s \(startDate) -j"
        return cmd
    }

    /// Executes the CLI command and returns the JSON output.
    /// Uses ShellExecutor for command execution and maps errors to CCUsageFetcherError.
    /// - Parameter command: The full CLI command to execute
    /// - Returns: The stdout data (JSON)
    /// - Throws: `CCUsageFetcherError` mapped from `ShellExecutorError`
    private func executeCLI(command: String) async throws -> Data {
        do {
            // Run the CLI and return raw stdout JSON.
            return try await shellExecutor.execute(command: command)
        } catch let error as ShellExecutorError {
            // Map shell execution errors into domain errors.
            throw mapShellError(error, command: command)
        }
    }

    /// Maps ShellExecutorError to CCUsageFetcherError for domain-specific error messages.
    /// - Parameters:
    ///   - error: The shell execution error
    ///   - command: The command that was executed (for error context)
    /// - Returns: A CCUsageFetcherError with appropriate message
    private func mapShellError(_ error: ShellExecutorError, command: String) -> CCUsageFetcherError {
        // Translate shell execution errors into ccusage-specific errors.
        switch error {
        case .launchFailed:
            return .cliNotFound(command: command)
        case .timeout:
            return .timeout
        case .executionFailed(let exitCode, let stderr):
            return .executionFailed(exitCode: exitCode, stderr: stderr)
        }
    }

    /// Parses the JSON response and builds a snapshot
    private func parseResponse(jsonData: Data, provider: TokenUsageProvider) throws -> TokenUsageSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let todayString = outputFormatter.string(from: now)

        // Calculate start of week (Sunday)
        var startOfWeekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        startOfWeekComponents.weekday = 1  // Sunday
        let startOfWeek = calendar.date(from: startOfWeekComponents) ?? now

        // Route to provider-specific parsing while sharing summary logic.
        switch provider {
        case .claude:
            return try parseClaudeResponse(
                jsonData: jsonData,
                provider: provider,
                todayString: todayString,
                startOfWeek: startOfWeek
            )
        case .codex:
            return try parseCodexResponse(
                jsonData: jsonData,
                provider: provider,
                todayString: todayString,
                startOfWeek: startOfWeek
            )
        }
    }

    /// Internal daily entry for parsing and aggregation.
    /// Distinct from shared `DailyUsageEntry` which uses ISO8601 dates only.
    private struct InternalDailyEntry {
        let date: String
        let totalTokens: Int
        let costUSD: Double
    }

    private struct UsageTotals {
        let totalTokens: Int
        let costUSD: Double
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, jsonData: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            // Decode JSON into the expected response model.
            return try decoder.decode(T.self, from: jsonData)
        } catch {
            throw CCUsageFetcherError.parseError(error.localizedDescription)
        }
    }

    private func buildSnapshot(
        provider: TokenUsageProvider,
        dailyEntries: [InternalDailyEntry],
        totals: UsageTotals,
        startOfWeek: Date,
        isTodayEntry: (InternalDailyEntry) -> Bool,
        parseDate: (InternalDailyEntry) -> Date?,
        normalizeToISO: (InternalDailyEntry) -> String
    ) -> TokenUsageSnapshot {
        // Build "today" usage from the daily entries.
        let todayEntry = dailyEntries.first(where: isTodayEntry)
        let today = TokenUsagePeriod(
            costUSD: todayEntry?.costUSD ?? 0,
            totalTokens: todayEntry?.totalTokens ?? 0
        )

        // Aggregate week totals from the start-of-week date.
        let weekEntries = dailyEntries.filter { entry in
            guard let date = parseDate(entry) else { return false }
            return date >= startOfWeek
        }
        let thisWeek = TokenUsagePeriod(
            costUSD: weekEntries.reduce(0) { $0 + $1.costUSD },
            totalTokens: weekEntries.reduce(0) { $0 + $1.totalTokens }
        )

        // Use CLI totals for month aggregation.
        let thisMonth = TokenUsagePeriod(
            costUSD: totals.costUSD,
            totalTokens: totals.totalTokens
        )

        // Build daily usage entries with normalized ISO8601 dates for heatmap.
        let dailyUsage = dailyEntries.map { entry in
            DailyUsageEntry(
                date: normalizeToISO(entry),
                totalTokens: entry.totalTokens
            )
        }

        return TokenUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            today: today,
            thisWeek: thisWeek,
            thisMonth: thisMonth,
            dailyUsage: dailyUsage
        )
    }

    /// Parses Claude (ccusage) response
    private func parseClaudeResponse(
        jsonData: Data,
        provider: TokenUsageProvider,
        todayString: String,
        startOfWeek: Date
    ) throws -> TokenUsageSnapshot {
        // Decode ccusage response and normalize fields.
        let response = try decodeResponse(CCUsageClaudeResponse.self, jsonData: jsonData)
        let dailyEntries = response.daily.map { entry in
            InternalDailyEntry(
                date: entry.date,
                totalTokens: entry.totalTokens,
                costUSD: entry.totalCost
            )
        }
        let totals = UsageTotals(
            totalTokens: response.totals.totalTokens,
            costUSD: response.totals.totalCost
        )
        // Build standardized snapshot from normalized entries.
        // Claude dates are already in ISO8601 format, so return as-is.
        return buildSnapshot(
            provider: provider,
            dailyEntries: dailyEntries,
            totals: totals,
            startOfWeek: startOfWeek,
            isTodayEntry: { $0.date == todayString },
            parseDate: { isoFormatter.date(from: $0.date) },
            normalizeToISO: { $0.date }
        )
    }

    /// Parses Codex (@ccusage/codex) response
    private func parseCodexResponse(
        jsonData: Data,
        provider: TokenUsageProvider,
        todayString: String,
        startOfWeek: Date
    ) throws -> TokenUsageSnapshot {
        // Decode @ccusage/codex response and normalize fields.
        let response = try decodeResponse(CCUsageCodexResponse.self, jsonData: jsonData)

        // Convert today's date to English format for comparison
        let todayDate = outputFormatter.date(from: todayString) ?? Date()
        let todayEnglish = englishFormatter.string(from: todayDate)
        // Normalize daily entries into a common structure.
        let dailyEntries = response.daily.map { entry in
            InternalDailyEntry(
                date: entry.date,
                totalTokens: entry.totalTokens,
                costUSD: entry.costUSD
            )
        }
        let totals = UsageTotals(
            totalTokens: response.totals.totalTokens,
            costUSD: response.totals.costUSD
        )
        // Build standardized snapshot from normalized entries.
        // Convert Codex English dates ("Dec 14, 2025") to ISO8601 ("2025-12-14").
        return buildSnapshot(
            provider: provider,
            dailyEntries: dailyEntries,
            totals: totals,
            startOfWeek: startOfWeek,
            isTodayEntry: { $0.date == todayEnglish },
            parseDate: { englishFormatter.date(from: $0.date) },
            normalizeToISO: { entry in
                guard let date = englishFormatter.date(from: entry.date) else {
                    return entry.date
                }
                return outputFormatter.string(from: date)
            }
        )
    }
}
