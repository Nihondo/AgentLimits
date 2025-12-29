// MARK: - TokenUsageModels.swift
// Shared data models for ccusage token usage tracking.
// Used by both App and Widget targets for displaying token costs.

import Foundation

// MARK: - Token Usage Provider

/// Provider identifier for ccusage CLI tools
enum TokenUsageProvider: String, Codable, CaseIterable, Identifiable {
    case codex       // @ccusage/codex (Codex)
    case claude      // ccusage (Claude Code)

    var id: String { rawValue }

    /// Display name for UI
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
        switch self {
        case .codex:
            return "npx -y @ccusage/codex@latest daily"
        case .claude:
            return "npx -y ccusage@latest daily"
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

    /// Deep link URL for widget tap action
    var widgetDeepLinkURL: URL {
        URL(string: "agentlimits://open-token-usage?provider=\(rawValue)")!
    }
}

// MARK: - Token Usage Period

/// Usage data for a specific time period (today/this week/this month)
struct TokenUsagePeriod: Codable, Equatable {
    /// Cost in USD
    let costUSD: Double
    /// Total tokens used
    let totalTokens: Int

    /// Zero usage period
    static let zero = TokenUsagePeriod(costUSD: 0, totalTokens: 0)
}

// MARK: - Token Usage Snapshot

/// Snapshot of token usage data fetched from ccusage CLI
struct TokenUsageSnapshot: Codable {
    let provider: TokenUsageProvider
    let fetchedAt: Date
    /// Today's usage
    let today: TokenUsagePeriod
    /// This week's usage (Sunday start)
    let thisWeek: TokenUsagePeriod
    /// This month's usage
    let thisMonth: TokenUsagePeriod
}

// MARK: - Token Usage Snapshot Store

/// Persists and retrieves token usage snapshots via App Group shared container.
final class TokenUsageSnapshotStore {
    static let shared = TokenUsageSnapshotStore()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        DateCodec.configureEncoder(encoder)
        DateCodec.configureDecoder(decoder)
    }

    /// Loads a snapshot for the specified provider from disk
    func loadSnapshot(for provider: TokenUsageProvider) -> TokenUsageSnapshot? {
        guard let url = snapshotFileURL(for: provider) else { return nil }
        return try? withSecurityScopedAccess(url) {
            let data = try Data(contentsOf: url)
            return try decoder.decode(TokenUsageSnapshot.self, from: data)
        }
    }

    /// Saves a snapshot to disk for later retrieval by widgets
    func saveSnapshot(_ snapshot: TokenUsageSnapshot) throws {
        guard let url = snapshotFileURL(for: snapshot.provider, createDirectory: true) else {
            throw UsageSnapshotStoreError.appGroupUnavailable
        }
        let data = try encoder.encode(snapshot)
        try withSecurityScopedAccess(url) {
            try data.write(to: url, options: .atomic)
        }
    }

    private func snapshotFileURL(for provider: TokenUsageProvider, createDirectory: Bool = false) -> URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else { return nil }
        let directoryURL = containerURL.appendingPathComponent(
            AppGroupConfig.snapshotDirectory, isDirectory: true
        )
        if createDirectory {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent(provider.snapshotFileName)
    }

    private func withSecurityScopedAccess<T>(_ url: URL, _ action: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try action()
    }
}

// MARK: - CCUsage Settings

/// Settings for ccusage CLI execution
struct CCUsageSettings: Codable, Equatable {
    let provider: TokenUsageProvider
    var isEnabled: Bool
    var additionalArgs: String

    /// Full CLI command with additional arguments
    var cliCommand: String {
        var cmd = provider.cliCommandBase
        if !additionalArgs.isEmpty {
            cmd += " " + additionalArgs
        }
        return cmd
    }

    /// CLI command for display (includes -s startDate -j)
    var displayCommand: String {
        var cmd = cliCommand
        cmd += " -s \(Self.currentStartOfMonth) -j"
        return cmd
    }

    /// Current month's start date in YYYYMMDD format
    private static var currentStartOfMonth: String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components) else {
            return "20251201"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: startOfMonth)
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
