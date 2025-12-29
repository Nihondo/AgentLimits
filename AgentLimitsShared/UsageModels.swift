// MARK: - UsageModels.swift
// Shared data models and storage for App and Widget targets.
// This file defines the core data structures for usage tracking and
// the snapshot store for persisting data via App Group.

import Foundation

// MARK: - Configuration

/// App Group configuration for shared data access between App and Widget
enum AppGroupConfig {
    static let groupId = "group.com.dmng.agentlimit"
    static let appLanguageKey = "app_language"
    static let snapshotKey = "UsageSnapshot"
    static let snapshotDirectory = "Library/Application Support/AgentLimit"
    static let usageRefreshIntervalMinutesKey = "usage_refresh_interval_minutes"
    static let tokenUsageRefreshIntervalMinutesKey = "token_usage_refresh_interval_minutes"
}

/// Localization configuration constants
enum LocalizationConfig {
    static let japaneseLanguageCode = "ja"
    static let englishLanguageCode = "en"
}

/// Auto-refresh interval configuration
enum UsageRefreshConfig {
    static var refreshIntervalMinutes: Int {
        UsageRefreshIntervalConfig.loadMinutes()
    }

    static var refreshIntervalSeconds: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    static var refreshIntervalDuration: Duration {
        .seconds(refreshIntervalMinutes * 60)
    }
}

/// Auto-refresh interval settings shared via App Group
enum RefreshIntervalConfig {
    static let defaultMinutes = 1
    static let minMinutes = 1
    static let maxMinutes = 10

    static var supportedMinutes: [Int] {
        Array(minMinutes...maxMinutes)
    }

    static func normalizedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, minMinutes), maxMinutes)
    }

    static func loadMinutes(
        from defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId),
        key: String
    ) -> Int {
        guard let defaults else { return defaultMinutes }
        let stored = defaults.object(forKey: key) as? Int
        return normalizedMinutes(stored ?? defaultMinutes)
    }

    static func saveMinutes(
        _ minutes: Int,
        to defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId),
        key: String
    ) {
        defaults?.set(normalizedMinutes(minutes), forKey: key)
    }
}

/// Auto-refresh interval settings for usage limits
enum UsageRefreshIntervalConfig {
    static func loadMinutes(
        from defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId)
    ) -> Int {
        guard let defaults else { return RefreshIntervalConfig.defaultMinutes }
        let stored = defaults.object(forKey: AppGroupConfig.usageRefreshIntervalMinutesKey) as? Int
        return RefreshIntervalConfig.normalizedMinutes(stored ?? RefreshIntervalConfig.defaultMinutes)
    }
}

/// Auto-refresh interval settings for ccusage token usage
enum TokenUsageRefreshConfig {
    static var refreshIntervalMinutes: Int {
        loadMinutes()
    }

    static var refreshIntervalSeconds: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    static var refreshIntervalDuration: Duration {
        .seconds(refreshIntervalMinutes * 60)
    }

    static func loadMinutes(
        from defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId)
    ) -> Int {
        guard let defaults else { return RefreshIntervalConfig.defaultMinutes }
        let stored = defaults.object(forKey: AppGroupConfig.tokenUsageRefreshIntervalMinutesKey) as? Int
        return RefreshIntervalConfig.normalizedMinutes(stored ?? RefreshIntervalConfig.defaultMinutes)
    }
}

/// Resolves language codes for localization
enum LanguageCodeResolver {
    /// Returns the system's preferred language code (ja or en)
    static func systemLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let preferredLanguage = preferredLanguages.first ?? LocalizationConfig.englishLanguageCode
        if preferredLanguage.hasPrefix(LocalizationConfig.japaneseLanguageCode) {
            return LocalizationConfig.japaneseLanguageCode
        }
        return LocalizationConfig.englishLanguageCode
    }

    /// Returns the effective language code for a given raw value, falling back to system language
    static func effectiveLanguageCode(for rawValue: String?) -> String {
        switch rawValue {
        case LocalizationConfig.japaneseLanguageCode:
            return LocalizationConfig.japaneseLanguageCode
        case LocalizationConfig.englishLanguageCode:
            return LocalizationConfig.englishLanguageCode
        default:
            return systemLanguageCode()
        }
    }
}

/// ISO8601 date encoding/decoding utilities for JSON serialization
enum DateCodec {
    private static let formatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let formatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Configures a JSONEncoder with ISO8601 date formatting
    static func configureEncoder(_ encoder: JSONEncoder) {
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatterWithFractionalSeconds.string(from: date))
        }
    }

    /// Configures a JSONDecoder with ISO8601 date parsing (with/without fractional seconds)
    static func configureDecoder(_ decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatterWithFractionalSeconds.date(from: value) {
                return date
            }
            if let date = formatterWithoutFractionalSeconds.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
    }
}

// MARK: - Data Models

/// Supported AI code assistant providers
enum UsageProvider: String, Codable, CaseIterable, Identifiable {
    case chatgptCodex
    case claudeCode

    var id: String { rawValue }

    /// Human-readable name for display in UI
    var displayName: String {
        switch self {
        case .chatgptCodex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        }
    }

    /// URL for the usage settings page of each provider
    var usageURL: URL {
        switch self {
        case .chatgptCodex:
            return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claudeCode:
            return URL(string: "https://claude.ai/settings/usage")!
        }
    }

    /// Host name for WebView page-ready detection
    var usageHost: String {
        switch self {
        case .chatgptCodex:
            return "chatgpt.com"
        case .claudeCode:
            return "claude.ai"
        }
    }

    /// Unique identifier for WidgetKit widget registration
    var widgetKind: String {
        switch self {
        case .chatgptCodex:
            return "AgentLimitWidget"
        case .claudeCode:
            return "AgentLimitWidgetClaude"
        }
    }

    /// Filename for persisted snapshot JSON
    var snapshotFileName: String {
        switch self {
        case .chatgptCodex:
            return "usage_snapshot.json"
        case .claudeCode:
            return "usage_snapshot_claude.json"
        }
    }

    /// Deep link URL for widget tap action
    var widgetDeepLinkURL: URL {
        URL(string: "agentlimits://open-usage?provider=\(rawValue)")!
    }
}

/// Usage window type: primary (5-hour) or secondary (weekly)
enum UsageWindowKind: String, Codable {
    /// Short-term usage window (5 hours)
    case primary
    /// Long-term usage window (7 days)
    case secondary
}

/// Represents a single usage limit window with percentage and reset time
struct UsageWindow: Codable {
    let kind: UsageWindowKind
    /// Usage percentage (0-100)
    let usedPercent: Double
    /// When the usage counter resets
    let resetAt: Date?
    /// Duration of the window in seconds
    let limitWindowSeconds: TimeInterval
}

/// A snapshot of usage data for a provider at a specific point in time
struct UsageSnapshot: Codable {
    let provider: UsageProvider
    /// When this snapshot was fetched
    let fetchedAt: Date
    /// 5-hour usage window
    let primaryWindow: UsageWindow?
    /// Weekly usage window
    let secondaryWindow: UsageWindow?
}

// MARK: - Storage

/// Errors that can occur when accessing the snapshot store
enum UsageSnapshotStoreError: Error {
    /// App Group container is not accessible
    case appGroupUnavailable
}

/// Persists and retrieves usage snapshots via App Group shared container.
/// Used by both the main app (for writing) and widgets (for reading).
final class UsageSnapshotStore {
    static let shared = UsageSnapshotStore()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        DateCodec.configureEncoder(self.encoder)
        DateCodec.configureDecoder(self.decoder)
    }

    /// Returns true if the App Group container is accessible
    var isAppGroupAvailable: Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId) != nil
    }

    /// Loads a snapshot for the specified provider from disk
    func loadSnapshot(for provider: UsageProvider) -> UsageSnapshot? {
        guard let url = snapshotFileURL(for: provider) else {
            return nil
        }
        return try? withSecurityScopedAccess(url) {
            let data = try Data(contentsOf: url)
            return try decoder.decode(UsageSnapshot.self, from: data)
        }
    }

    /// Saves a snapshot to disk for later retrieval by widgets
    func saveSnapshot(_ snapshot: UsageSnapshot) throws {
        guard let url = snapshotFileURL(for: snapshot.provider, createDirectory: true) else {
            throw UsageSnapshotStoreError.appGroupUnavailable
        }
        let data = try encoder.encode(snapshot)
        try withSecurityScopedAccess(url) {
            try data.write(to: url, options: .atomic)
        }
    }

    private func snapshotFileURL(for provider: UsageProvider, createDirectory: Bool = false) -> URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId) else {
            return nil
        }
        let directoryURL = containerURL.appendingPathComponent(AppGroupConfig.snapshotDirectory, isDirectory: true)
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
