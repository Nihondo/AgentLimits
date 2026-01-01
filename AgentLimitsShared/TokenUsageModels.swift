// MARK: - TokenUsageModels.swift
// Shared data models for ccusage token usage tracking.
// Used by both App and Widget targets for displaying token costs.

import Foundation

// MARK: - Token Usage Provider

/// Provider identifier for ccusage CLI tools.
/// Uses `codex` and `claude` as rawValue for JSON compatibility.
enum TokenUsageProvider: String, Codable, CaseIterable, Identifiable, SnapshotFileNaming, AIProviderProtocol {
    case codex       // @ccusage/codex (Codex)
    case claude      // ccusage (Claude Code)

    var id: String { rawValue }

    /// Display name for UI (implements AIProviderProtocol)
    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        }
    }

    /// Display name for widget title
    var widgetDisplayName: String {
        switch self {
        case .codex:
            return "ccusage (Codex)"
        case .claude:
            return "ccusage (Claude)"
        }
    }

    /// Base CLI command (without arguments)
    var cliCommandBase: String {
        let npxExecutable = CLICommandPathResolver.resolveExecutable(for: .npx, defaultName: "npx")
        switch self {
        case .codex:
            return "\(npxExecutable) -y @ccusage/codex@latest daily"
        case .claude:
            return "\(npxExecutable) -y ccusage@latest daily"
        }
    }

    /// Widget kind identifier for WidgetKit
    var widgetKind: String {
        switch self {
        case .codex:
            return "TokenUsageWidgetCodex"
        case .claude:
            return "TokenUsageWidgetClaude"
        }
    }

    /// Snapshot filename for App Group storage
    var snapshotFileName: String {
        switch self {
        case .codex:
            return "token_usage_codex.json"
        case .claude:
            return "token_usage_claude.json"
        }
    }

    /// Deep link URL for widget tap action.
    /// Constructs a URL with the provider's rawValue as a query parameter.
    var widgetDeepLinkURL: URL {
        guard let url = URL(string: "agentlimits://open-token-usage?provider=\(rawValue)") else {
            preconditionFailure("Invalid deep link URL for token usage provider: \(rawValue)")
        }
        return url
    }

    // MARK: - Provider Conversion

    /// Converts this TokenUsageProvider to its corresponding UsageProvider.
    /// Useful when working with Usage Limits features for the same AI provider.
    var usageProvider: UsageProvider {
        switch self {
        case .codex:
            return .chatgptCodex
        case .claude:
            return .claudeCode
        }
    }
}

// MARK: - Token Usage Period

/// Usage data for a specific time period (today/this week/this month)
struct TokenUsagePeriod: Codable, Equatable {
    /// Cost in USD
    let costUSD: Double
    /// Total tokens used
    let totalTokens: Int
}

// MARK: - Daily Usage Entry

/// Daily usage data entry for heatmap display
struct DailyUsageEntry: Codable, Equatable {
    /// Date in ISO8601 format (YYYY-MM-DD)
    let date: String
    /// Total tokens used on this day
    let totalTokens: Int
}

// MARK: - Token Usage Snapshot

/// Snapshot of token usage data fetched from ccusage CLI
struct TokenUsageSnapshot: Codable, SnapshotData {
    let provider: TokenUsageProvider
    let fetchedAt: Date
    /// Today's usage
    let today: TokenUsagePeriod
    /// This week's usage (Sunday start)
    let thisWeek: TokenUsagePeriod
    /// This month's usage
    let thisMonth: TokenUsagePeriod
    /// Daily usage entries for the current month (for heatmap)
    let dailyUsage: [DailyUsageEntry]

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case provider, fetchedAt, today, thisWeek, thisMonth, dailyUsage
    }

    // MARK: - Initializers

    /// Standard initializer with all properties
    init(
        provider: TokenUsageProvider,
        fetchedAt: Date,
        today: TokenUsagePeriod,
        thisWeek: TokenUsagePeriod,
        thisMonth: TokenUsagePeriod,
        dailyUsage: [DailyUsageEntry] = []
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.today = today
        self.thisWeek = thisWeek
        self.thisMonth = thisMonth
        self.dailyUsage = dailyUsage
    }

    /// Custom Decodable for backward compatibility with existing snapshots
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(TokenUsageProvider.self, forKey: .provider)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        today = try container.decode(TokenUsagePeriod.self, forKey: .today)
        thisWeek = try container.decode(TokenUsagePeriod.self, forKey: .thisWeek)
        thisMonth = try container.decode(TokenUsagePeriod.self, forKey: .thisMonth)
        // Optional for backward compatibility with existing snapshots without dailyUsage
        dailyUsage = try container.decodeIfPresent([DailyUsageEntry].self, forKey: .dailyUsage) ?? []
    }
}

// MARK: - Token Usage Snapshot Store

/// Persists and retrieves token usage snapshots via App Group shared container.
/// Used by both the main app (for writing) and widgets (for reading).
/// Inherits common functionality from AppGroupSnapshotStore.
final class TokenUsageSnapshotStore: AppGroupSnapshotStore<TokenUsageProvider, TokenUsageSnapshot> {
    /// Shared singleton instance for app-wide use
    static let shared = TokenUsageSnapshotStore()
}

// MARK: - CCUsage Settings

/// Resolves the current month's start date string for ccusage CLI commands.
enum MonthStartDateResolver {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Calculates the first day of the current month in YYYYMMDD format.
    /// - Parameters:
    ///   - now: The date to base the calculation on (default: current date)
    ///   - calendar: The calendar used for component extraction (default: .current)
    /// - Returns: Date string in compact format (e.g., "20251201")
    static func calculateStartOfMonthString(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        // Extract year/month and rebuild the first day of the month.
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components) else {
            // Fallback to the provided date when calendar calculation fails.
            return formatter.string(from: now)
        }
        return formatter.string(from: startOfMonth)
    }
}

/// Pre-validated ccusage external link URLs.
enum CCUsageLinks {
    /// ccusage website URL
    static let siteURL = URL(string: "https://ccusage.com/")
    /// ccusage GitHub repository URL
    static let repoURL = URL(string: "https://github.com/ryoppippi/ccusage")
}

/// Settings for ccusage CLI execution
struct CCUsageSettings: Codable, Equatable {
    let provider: TokenUsageProvider
    var isEnabled: Bool
    var additionalArgs: String

    /// Full CLI command with additional arguments
    var cliCommand: String {
        // Append additional args only when provided by user.
        var cmd = provider.cliCommandBase
        if !additionalArgs.isEmpty {
            cmd += " " + additionalArgs
        }
        return cmd
    }

    /// CLI command for display (includes -s startDate -j)
    var displayCommand: String {
        // Include start date and JSON flag for UI display.
        var cmd = cliCommand
        cmd += " -s \(Self.currentStartOfMonth) -j"
        return cmd
    }

    /// Current month's start date in YYYYMMDD format
    private static var currentStartOfMonth: String {
        MonthStartDateResolver.calculateStartOfMonthString()
    }

    /// Default settings for a provider
    static func defaultSettings(for provider: TokenUsageProvider) -> CCUsageSettings {
        CCUsageSettings(provider: provider, isEnabled: false, additionalArgs: "")
    }
}

// MARK: - CCUsage Settings Store

/// Persists ccusage settings to UserDefaults
final class CCUsageSettingsStore {
    static let shared = CCUsageSettingsStore()

    private let userDefaults: UserDefaults
    private let key = "ccusage_settings"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Loads settings for all providers
    func loadSettings() -> [TokenUsageProvider: CCUsageSettings] {
        guard let data = userDefaults.data(forKey: key),
              let settingsArray = try? decoder.decode([CCUsageSettings].self, from: data) else {
            return defaultSettings()
        }
        var result: [TokenUsageProvider: CCUsageSettings] = [:]
        for settings in settingsArray {
            result[settings.provider] = settings
        }
        // Ensure all providers have settings
        for provider in TokenUsageProvider.allCases where result[provider] == nil {
            result[provider] = .defaultSettings(for: provider)
        }
        return result
    }

    /// Saves settings for all providers
    func saveSettings(_ settings: [TokenUsageProvider: CCUsageSettings]) {
        let settingsArray = Array(settings.values)
        if let data = try? encoder.encode(settingsArray) {
            userDefaults.set(data, forKey: key)
        }
    }

    /// Updates settings for a single provider
    func updateSettings(_ settings: CCUsageSettings) {
        var allSettings = loadSettings()
        allSettings[settings.provider] = settings
        saveSettings(allSettings)
    }

    private func defaultSettings() -> [TokenUsageProvider: CCUsageSettings] {
        var result: [TokenUsageProvider: CCUsageSettings] = [:]
        for provider in TokenUsageProvider.allCases {
            result[provider] = .defaultSettings(for: provider)
        }
        return result
    }
}
