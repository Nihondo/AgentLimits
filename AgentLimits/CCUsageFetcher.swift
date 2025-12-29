// MARK: - CCUsageFetcher.swift
// Executes ccusage CLI commands and parses JSON output to fetch token usage data.

import Foundation
@preconcurrency import Dispatch

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
    case noData

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
        case .noData:
            return "No usage data available"
        }
    }
}

// MARK: - CCUsage Fetcher

/// Executes ccusage CLI commands and parses the JSON output
final class CCUsageFetcher {
    private let timeout: TimeInterval
    private let settingsStore: CCUsageSettingsStore

    // Date formatters for parsing
    private let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let englishFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(timeout: TimeInterval = 60, settingsStore: CCUsageSettingsStore = .shared) {
        self.timeout = timeout
        self.settingsStore = settingsStore
    }

    /// Fetches a token usage snapshot for the specified provider
    func fetchSnapshot(for provider: TokenUsageProvider) async throws -> TokenUsageSnapshot {
        let settings = settingsStore.loadSettings()[provider] ?? .defaultSettings(for: provider)
        let startOfMonth = calculateStartOfMonth()
        let command = buildCommand(settings: settings, startDate: startOfMonth)
        let jsonData = try await executeCLI(command: command)
        return try parseResponse(jsonData: jsonData, provider: provider)
    }

    // MARK: - Private Methods

    /// Calculates the first day of the current month in YYYYMMDD format
    private func calculateStartOfMonth() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components) else {
            return outputFormatter.string(from: now).replacingOccurrences(of: "-", with: "")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: startOfMonth)
    }

    /// Builds the full CLI command with arguments
    private func buildCommand(settings: CCUsageSettings, startDate: String) -> String {
        var cmd = settings.cliCommand
        cmd += " -s \(startDate) -j"
        return cmd
    }

    /// Executes the CLI command and returns the JSON output
    private func executeCLI(command: String) async throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CCUsageFetcherError.cliNotFound(command: command))
                return
            }

            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )

            process.terminationHandler = { proc in
                timeoutWorkItem.cancel()

                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if proc.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CCUsageFetcherError.timeout)
                } else if proc.terminationStatus != 0 {
                    continuation.resume(throwing: CCUsageFetcherError.executionFailed(
                        exitCode: proc.terminationStatus,
                        stderr: errorOutput
                    ))
                } else {
                    continuation.resume(returning: outputData)
                }
            }
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

    /// Parses Claude (ccusage) response
    private func parseClaudeResponse(
        jsonData: Data,
        provider: TokenUsageProvider,
        todayString: String,
        startOfWeek: Date
    ) throws -> TokenUsageSnapshot {
        let decoder = JSONDecoder()
        let response: CCUsageClaudeResponse
        do {
            response = try decoder.decode(CCUsageClaudeResponse.self, from: jsonData)
        } catch {
            throw CCUsageFetcherError.parseError(error.localizedDescription)
        }

        // Today's data
        let todayEntry = response.daily.first { $0.date == todayString }
        let today = TokenUsagePeriod(
            costUSD: todayEntry?.totalCost ?? 0,
            totalTokens: todayEntry?.totalTokens ?? 0
        )

        // This week's data (aggregate from startOfWeek)
        let weekEntries = response.daily.filter { entry in
            guard let date = isoFormatter.date(from: entry.date) else { return false }
            return date >= startOfWeek
        }
        let thisWeek = TokenUsagePeriod(
            costUSD: weekEntries.reduce(0) { $0 + $1.totalCost },
            totalTokens: weekEntries.reduce(0) { $0 + $1.totalTokens }
        )

        // This month's data (from totals)
        let thisMonth = TokenUsagePeriod(
            costUSD: response.totals.totalCost,
            totalTokens: response.totals.totalTokens
        )

        return TokenUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            today: today,
            thisWeek: thisWeek,
            thisMonth: thisMonth
        )
    }

    /// Parses Codex (@ccusage/codex) response
    private func parseCodexResponse(
        jsonData: Data,
        provider: TokenUsageProvider,
        todayString: String,
        startOfWeek: Date
    ) throws -> TokenUsageSnapshot {
        let decoder = JSONDecoder()
        let response: CCUsageCodexResponse
        do {
            response = try decoder.decode(CCUsageCodexResponse.self, from: jsonData)
        } catch {
            throw CCUsageFetcherError.parseError(error.localizedDescription)
        }

        // Convert today's date to English format for comparison
        let todayDate = outputFormatter.date(from: todayString) ?? Date()
        let todayEnglish = englishFormatter.string(from: todayDate)

        // Today's data
        let todayEntry = response.daily.first { $0.date == todayEnglish }
        let today = TokenUsagePeriod(
            costUSD: todayEntry?.costUSD ?? 0,
            totalTokens: todayEntry?.totalTokens ?? 0
        )

        // This week's data (aggregate from startOfWeek)
        let weekEntries = response.daily.filter { entry in
            guard let date = englishFormatter.date(from: entry.date) else { return false }
            return date >= startOfWeek
        }
        let thisWeek = TokenUsagePeriod(
            costUSD: weekEntries.reduce(0) { $0 + $1.costUSD },
            totalTokens: weekEntries.reduce(0) { $0 + $1.totalTokens }
        )

        // This month's data (from totals)
        let thisMonth = TokenUsagePeriod(
            costUSD: response.totals.costUSD,
            totalTokens: response.totals.totalTokens
        )

        return TokenUsageSnapshot(
            provider: provider,
            fetchedAt: Date(),
            today: today,
            thisWeek: thisWeek,
            thisMonth: thisMonth
        )
    }
}
