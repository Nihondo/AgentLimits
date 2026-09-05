// MARK: - TokenUsageModels.swift
// Shared data models for ccusage token usage tracking.
// Used by both App and Widget targets for displaying token costs.

import Foundation

// MARK: - Token Usage Provider

/// Provider identifier for token usage tracking.
/// Uses `codex`, `claude`, and `copilot` as rawValue for JSON compatibility.
enum TokenUsageProvider: String, Codable, CaseIterable, Identifiable, SnapshotFileNaming, AIProviderProtocol {
    case codex       // ccusage codex (Codex)
    case claude      // ccusage claude (Claude Code)
    case copilot     // GitHub Copilot billing (WebView-based)

    var id: String { rawValue }

    /// Whether this provider uses CLI-based fetching.
    /// Copilot uses WebView-based fetch instead.
    var isCLIBased: Bool {
        switch self {
        case .codex, .claude:
            return true
        case .copilot:
            return false
        }
    }

    /// Display name for UI (implements AIProviderProtocol)
    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        case .copilot:
            return "Copilot"
        }
    }

    /// Display name for widget title
    var widgetDisplayName: String {
        switch self {
        case .codex:
            return "Codex usage"
        case .claude:
            return "Claude Code usage"
        case .copilot:
            return "Copilot usage"
        }
    }

    /// Base CLI command (without arguments).
    /// Returns empty string for non-CLI providers.
    var cliCommandBase: String {
        let npxExecutable = CLICommandPathResolver.resolveExecutable(for: .npx, defaultName: "npx")
        switch self {
        case .codex:
            return "\(npxExecutable) -y ccusage@latest codex daily"
        case .claude:
            return "\(npxExecutable) -y ccusage@latest claude daily"
        case .copilot:
            return ""
        }
    }

    /// Widget kind identifier for WidgetKit
    var widgetKind: String {
        switch self {
        case .codex:
            return "TokenUsageWidgetCodex"
        case .claude:
            return "TokenUsageWidgetClaude"
        case .copilot:
            return "TokenUsageWidgetCopilot"
        }
    }

    /// Snapshot filename for App Group storage
    var snapshotFileName: String {
        switch self {
        case .codex:
            return "token_usage_codex.json"
        case .claude:
            return "token_usage_claude.json"
        case .copilot:
            return "token_usage_copilot.json"
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
        case .copilot:
            return .githubCopilot
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
typealias TokenUsageSnapshotStore = AppGroupSnapshotStore<TokenUsageProvider, TokenUsageSnapshot>

extension AppGroupSnapshotStore where Provider == TokenUsageProvider, Snapshot == TokenUsageSnapshot {
    /// Shared store instance for app-wide use.
    static let shared = Self()
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

/// Placeholders usable inside a user-edited command template.
enum CCUsageCommandPlaceholder {
    /// Replaced with the current month's start date (YYYYMMDD) at execution time.
    static let since = "{{since}}"
}

/// Settings for ccusage CLI execution
struct CCUsageSettings: Codable, Equatable {
    let provider: TokenUsageProvider
    var isEnabled: Bool
    /// User-edited full command template. Empty means "use the generated default".
    var commandTemplate: String

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case provider, isEnabled, commandTemplate
    }

    /// Key for the `additionalArgs` field used by settings saved before it was
    /// folded into `commandTemplate`. Kept separate from `CodingKeys` so
    /// Encodable synthesis (which requires every case to map to a stored
    /// property) is unaffected.
    private enum LegacyCodingKeys: String, CodingKey {
        case additionalArgs
    }

    // MARK: - Initializers

    /// Standard initializer with all properties.
    init(
        provider: TokenUsageProvider,
        isEnabled: Bool,
        commandTemplate: String = ""
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.commandTemplate = commandTemplate
    }

    /// Custom Decodable for backward compatibility with settings saved before
    /// `commandTemplate` existed (and after the removal of the separate
    /// `additionalArgs` field, which is folded into `commandTemplate` here so
    /// previously configured arguments keep working unchanged).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decode(TokenUsageProvider.self, forKey: .provider)
        self.provider = provider
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)

        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)

        if let template = try container.decodeIfPresent(String.self, forKey: .commandTemplate),
           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commandTemplate = template
        } else if let legacyArgs = try legacyContainer?.decodeIfPresent(String.self, forKey: .additionalArgs),
                  !legacyArgs.isEmpty {
            // Legacy settings stored additional args separately; bake them into
            // an equivalent explicit template so behavior is unchanged.
            var cmd = provider.cliCommandBase
            cmd += " " + legacyArgs
            cmd += " --since \(CCUsageCommandPlaceholder.since) -j"
            commandTemplate = cmd
        } else {
            commandTemplate = ""
        }
    }

    /// Whether the user has replaced the generated default with a custom command.
    var isCommandCustomized: Bool {
        !commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Generated default template (base command + since/json flags) used
    /// whenever the user hasn't edited the command.
    var defaultCommandTemplate: String {
        "\(provider.cliCommandBase) --since \(CCUsageCommandPlaceholder.since) -j"
    }

    /// Template actually used to build the executed command.
    var resolvedCommandTemplate: String {
        isCommandCustomized ? commandTemplate : defaultCommandTemplate
    }

    /// CLI command for display (placeholders expanded using the current month's start date)
    var displayCommand: String {
        makeCLICommand(startDate: Self.currentStartOfMonth)
    }

    /// Builds the full CLI command by expanding placeholders in the resolved template.
    /// - Parameter startDate: Start date in YYYYMMDD format.
    /// - Returns: CLI command string with placeholders expanded.
    func makeCLICommand(startDate: String) -> String {
        resolvedCommandTemplate.replacingOccurrences(
            of: CCUsageCommandPlaceholder.since,
            with: startDate
        )
    }

    /// Current month's start date in YYYYMMDD format
    private static var currentStartOfMonth: String {
        MonthStartDateResolver.calculateStartOfMonthString()
    }

    /// Default settings for a provider
    static func defaultSettings(for provider: TokenUsageProvider) -> CCUsageSettings {
        CCUsageSettings(provider: provider, isEnabled: false)
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
