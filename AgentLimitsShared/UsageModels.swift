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
    static let snapshotDirectory = "Library/Application Support/AgentLimit"
    static let usageRefreshIntervalMinutesKey = "usage_refresh_interval_minutes"
    static let tokenUsageRefreshIntervalMinutesKey = "token_usage_refresh_interval_minutes"
}

/// Shared UserDefaults keys used by app + widget
enum SharedUserDefaultsKeys {
    static let displayMode = "usage_display_mode"
    static let cachedDisplayMode = "usage_display_mode_cached"
}

// MARK: - CLI Command Paths

/// UserDefaults keys for CLI command path overrides.
enum CLICommandPathKeys {
    static let codex = "cli_path_codex"
    static let claude = "cli_path_claude"
    static let npx = "cli_path_npx"
}

/// CLI command kinds that support path overrides.
enum CLICommandKind: String, CaseIterable, Identifiable {
    case codex
    case claude
    case npx

    var id: String { rawValue }
}

/// Resolves CLI executable names using optional full-path overrides.
enum CLICommandPathResolver {
    /// Returns the executable path to use for a command.
    /// - Parameters:
    ///   - kind: Command kind that may have a path override.
    ///   - defaultName: Default executable name to use when no override is set.
    static func resolveExecutable(for kind: CLICommandKind, defaultName: String) -> String {
        guard let overridePath = loadCommandPath(for: kind) else {
            return defaultName
        }
        return overridePath
    }

    private static func loadCommandPath(for kind: CLICommandKind) -> String? {
        let defaults = UserDefaults(suiteName: AppGroupConfig.groupId) ?? .standard
        let key = commandPathKey(for: kind)
        let rawValue = defaults.string(forKey: key) ?? ""
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func commandPathKey(for kind: CLICommandKind) -> String {
        switch kind {
        case .codex:
            return CLICommandPathKeys.codex
        case .claude:
            return CLICommandPathKeys.claude
        case .npx:
            return CLICommandPathKeys.npx
        }
    }
}

/// Raw display mode values persisted to shared UserDefaults.
enum UsageDisplayModeRaw: String {
    case used
    case remaining
}

/// Localization configuration constants
enum LocalizationConfig {
    static let japaneseLanguageCode = "ja"
    static let englishLanguageCode = "en"
}

// MARK: - Usage Status Levels

/// Usage status level derived from usage percentage.
enum UsageStatusLevel {
    case green
    case orange
    case red
}

/// Resolves usage status level based on percent and display mode.
enum UsageStatusLevelResolver {
    /// Returns the status level for a percentage in the current display mode.
    /// - Parameters:
    ///   - percent: Percent value in the current display mode.
    ///   - isRemainingMode: Whether the display mode is "remaining".
    ///   - warningThreshold: Warning threshold percentage for used mode.
    ///   - dangerThreshold: Danger threshold percentage for used mode.
    static func level(
        for percent: Double,
        isRemainingMode: Bool,
        warningThreshold: Int = UsageStatusThresholdDefaults.warningPercent,
        dangerThreshold: Int = UsageStatusThresholdDefaults.dangerPercent
    ) -> UsageStatusLevel {
        // Normalize input to a 0-100 range before threshold evaluation.
        let clamped = max(0, min(100, percent))
        let normalizedWarning = clampThreshold(warningThreshold)
        let normalizedDanger = clampThreshold(dangerThreshold)
        let usedWarning = min(normalizedWarning, normalizedDanger)
        let usedDanger = max(normalizedWarning, normalizedDanger)
        // Remaining-mode thresholds invert the semantics (low remaining => warning).
        if isRemainingMode {
            let remainingDanger = 100 - usedDanger
            let remainingWarning = 100 - usedWarning
            if clamped <= Double(remainingDanger) { return .red }
            if clamped <= Double(remainingWarning) { return .orange }
            return .green
        }
        // Used-mode thresholds (high usage => warning).
        if clamped >= Double(usedDanger) { return .red }
        if clamped >= Double(usedWarning) { return .orange }
        return .green
    }

    private static func clampThreshold(_ value: Int) -> Int {
        min(max(value, 1), 100)
    }
}

// MARK: - Usage Status Thresholds

/// Default thresholds for usage status coloring.
enum UsageStatusThresholdDefaults {
    static let warningPercent = 70
    static let dangerPercent = 90
}

/// Thresholds used for coloring usage percentages.
struct UsageStatusThresholds: Codable, Equatable {
    let warningPercent: Int
    let dangerPercent: Int
}

/// Stores per-provider, per-window thresholds in App Group defaults for coloring.
enum UsageStatusThresholdStore {
    static let revisionKey = "usage_color_threshold_revision"

    static func loadThresholds(
        for provider: UsageProvider,
        windowKind: UsageWindowKind
    ) -> UsageStatusThresholds {
        let defaults = UserDefaults(suiteName: AppGroupConfig.groupId)
        let warning = loadPercent(
            from: defaults,
            key: makeWarningKey(provider: provider, windowKind: windowKind),
            fallback: UsageStatusThresholdDefaults.warningPercent
        )
        let danger = loadPercent(
            from: defaults,
            key: makeDangerKey(provider: provider, windowKind: windowKind),
            fallback: UsageStatusThresholdDefaults.dangerPercent
        )
        return UsageStatusThresholds(warningPercent: warning, dangerPercent: danger)
    }

    static func saveThresholds(
        _ thresholds: UsageStatusThresholds,
        for provider: UsageProvider,
        windowKind: UsageWindowKind
    ) {
        let defaults = UserDefaults(suiteName: AppGroupConfig.groupId)
        defaults?.set(thresholds.warningPercent, forKey: makeWarningKey(provider: provider, windowKind: windowKind))
        defaults?.set(thresholds.dangerPercent, forKey: makeDangerKey(provider: provider, windowKind: windowKind))
    }

    static func bumpRevision() {
        let defaults = UserDefaults(suiteName: AppGroupConfig.groupId)
        defaults?.set(Date().timeIntervalSince1970, forKey: revisionKey)
    }

    private static func loadPercent(from defaults: UserDefaults?, key: String, fallback: Int) -> Int {
        guard let storedValue = defaults?.object(forKey: key) as? Int else {
            return fallback
        }
        return min(max(storedValue, 1), 100)
    }

    private static func makeWarningKey(provider: UsageProvider, windowKind: UsageWindowKind) -> String {
        "usage_color_threshold_warning_\(provider.rawValue)_\(windowKind.rawValue)"
    }

    private static func makeDangerKey(provider: UsageProvider, windowKind: UsageWindowKind) -> String {
        "usage_color_threshold_danger_\(provider.rawValue)_\(windowKind.rawValue)"
    }
}

// MARK: - Usage Percent Formatting

/// Formats usage percentage text for UI display.
enum UsagePercentFormatter {
    /// Returns a percent string for display (e.g. "75%").
    /// - Parameters:
    ///   - percent: Percent value already converted to the display mode.
    ///   - placeholder: Placeholder used when percent is nil.
    static func formatPercentText(_ percent: Double?, placeholder: String = "--%") -> String {
        // Use placeholder when no value is available.
        guard let percent else { return placeholder }
        // Clamp to a valid range before formatting.
        let clamped = max(0, min(100, percent))
        return String(format: "%.0f%%", clamped)
    }
}

// MARK: - Refresh Interval Configuration

/// Auto-refresh interval settings shared via App Group.
/// Provides common constants and utility methods for interval configuration.
enum RefreshIntervalConfig {
    /// Default refresh interval in minutes
    static let defaultMinutes = 1
    /// Minimum allowed refresh interval in minutes
    static let minMinutes = 1
    /// Maximum allowed refresh interval in minutes
    static let maxMinutes = 10

    /// Array of all supported interval values for UI picker
    static var supportedMinutes: [Int] {
        Array(minMinutes...maxMinutes)
    }

    /// Clamps the given minutes value to the valid range [minMinutes, maxMinutes]
    /// - Parameter minutes: The raw minutes value to normalize
    /// - Returns: The clamped value within valid bounds
    static func normalizedMinutes(_ minutes: Int) -> Int {
        // Clamp to the supported range to avoid invalid settings.
        min(max(minutes, minMinutes), maxMinutes)
    }

    /// Loads the refresh interval from UserDefaults for a given key.
    /// - Parameters:
    ///   - defaults: The UserDefaults instance to read from (defaults to App Group)
    ///   - key: The UserDefaults key for the interval setting
    /// - Returns: The stored interval, or defaultMinutes if not set
    static func loadMinutes(
        from defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId),
        key: String
    ) -> Int {
        // Fall back to defaults when shared defaults are unavailable.
        guard let defaults else { return defaultMinutes }
        // Read and normalize the stored value.
        let stored = defaults.object(forKey: key) as? Int
        return normalizedMinutes(stored ?? defaultMinutes)
    }
}

/// Provides convenient access to refresh interval settings for a specific feature.
/// Encapsulates the UserDefaults key and provides computed properties for different time units.
struct RefreshIntervalAccessor {
    /// The UserDefaults key for this feature's refresh interval
    private let key: String

    /// Creates an accessor for the specified UserDefaults key
    /// - Parameter key: The key to read the interval from
    init(key: String) {
        self.key = key
    }

    /// The refresh interval in minutes
    var refreshIntervalMinutes: Int {
        RefreshIntervalConfig.loadMinutes(
            from: UserDefaults(suiteName: AppGroupConfig.groupId),
            key: key
        )
    }

    /// The refresh interval in seconds (for TimeInterval-based APIs)
    var refreshIntervalSeconds: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    /// The refresh interval as Duration (for Swift Concurrency sleep)
    var refreshIntervalDuration: Duration {
        .seconds(refreshIntervalMinutes * 60)
    }
}

/// Auto-refresh interval configuration for usage limits (Codex/Claude).
/// Provides static accessors for the usage limits refresh interval.
enum UsageRefreshConfig {
    /// Shared accessor instance for usage limits interval
    private static let accessor = RefreshIntervalAccessor(
        key: AppGroupConfig.usageRefreshIntervalMinutesKey
    )

    /// The refresh interval in minutes
    static var refreshIntervalMinutes: Int { accessor.refreshIntervalMinutes }
    /// The refresh interval in seconds
    static var refreshIntervalSeconds: TimeInterval { accessor.refreshIntervalSeconds }
    /// The refresh interval as Duration
    static var refreshIntervalDuration: Duration { accessor.refreshIntervalDuration }
}

/// Auto-refresh interval configuration for ccusage token usage.
/// Provides static accessors for the token usage refresh interval.
enum TokenUsageRefreshConfig {
    /// Shared accessor instance for token usage interval
    private static let accessor = RefreshIntervalAccessor(
        key: AppGroupConfig.tokenUsageRefreshIntervalMinutesKey
    )

    /// The refresh interval in minutes
    static var refreshIntervalMinutes: Int { accessor.refreshIntervalMinutes }
    /// The refresh interval in seconds
    static var refreshIntervalSeconds: TimeInterval { accessor.refreshIntervalSeconds }
    /// The refresh interval as Duration
    static var refreshIntervalDuration: Duration { accessor.refreshIntervalDuration }
}

/// Resolves language codes for localization
enum LanguageCodeResolver {
    /// Returns the system's preferred language code (ja or en)
    static func systemLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        // Pick the first preferred language and normalize to supported codes.
        let preferredLanguage = preferredLanguages.first ?? LocalizationConfig.englishLanguageCode
        if preferredLanguage.hasPrefix(LocalizationConfig.japaneseLanguageCode) {
            return LocalizationConfig.japaneseLanguageCode
        }
        return LocalizationConfig.englishLanguageCode
    }

    /// Returns the effective language code for a given raw value, falling back to system language
    static func effectiveLanguageCode(for rawValue: String?) -> String {
        // Respect explicit selection when available; otherwise use system setting.
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
            // Encode using fractional seconds for higher precision.
            var container = encoder.singleValueContainer()
            try container.encode(formatterWithFractionalSeconds.string(from: date))
        }
    }

    /// Configures a JSONDecoder with ISO8601 date parsing (with/without fractional seconds)
    static func configureDecoder(_ decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            // Attempt parsing with fractional seconds, then without as fallback.
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

// MARK: - Common AI Provider Protocol

/// Common protocol for AI code assistant provider types.
/// Provides shared properties for display and identification.
/// Both `UsageProvider` and `TokenUsageProvider` conform to this protocol.
protocol AIProviderProtocol: Hashable, CaseIterable, Identifiable where ID == String {
    /// Human-readable name for display in UI
    var displayName: String { get }
}

// MARK: - Data Models

/// Supported AI code assistant providers for Usage Limits tracking.
/// Uses `chatgptCodex` and `claudeCode` as rawValue for JSON compatibility.
enum UsageProvider: String, Codable, CaseIterable, Identifiable, SnapshotFileNaming, AIProviderProtocol {
    case chatgptCodex
    case claudeCode

    var id: String { rawValue }

    // MARK: - Static URL Constants
    // Pre-validated URL constants to avoid force unwrapping at runtime.
    // These are defined as static properties to ensure they are only created once.

    /// Codex usage settings page URL
    private static let codexUsageURL = URL(string: "https://chatgpt.com/codex/settings/usage")
    /// Claude usage settings page URL
    private static let claudeUsageURL = URL(string: "https://claude.ai/settings/usage")

    // MARK: - Instance Properties

    /// Human-readable name for display in UI
    var displayName: String {
        switch self {
        case .chatgptCodex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        }
    }

    /// URL for the usage settings page of each provider.
    /// Returns a pre-validated static URL constant.
    var usageURL: URL {
        switch self {
        case .chatgptCodex:
            guard let url = Self.codexUsageURL else {
                preconditionFailure("Invalid static URL: codexUsageURL")
            }
            return url
        case .claudeCode:
            guard let url = Self.claudeUsageURL else {
                preconditionFailure("Invalid static URL: claudeUsageURL")
            }
            return url
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

    /// Deep link URL for widget tap action.
    /// Constructs a URL with the provider's rawValue as a query parameter.
    var widgetDeepLinkURL: URL {
        guard let url = URL(string: "agentlimits://open-usage?provider=\(rawValue)") else {
            preconditionFailure("Invalid deep link URL for provider: \(rawValue)")
        }
        return url
    }

    // MARK: - Provider Conversion

    /// Converts this UsageProvider to its corresponding TokenUsageProvider.
    /// Useful when working with ccusage CLI features for the same AI provider.
    var tokenUsageProvider: TokenUsageProvider {
        switch self {
        case .chatgptCodex:
            return .codex
        case .claudeCode:
            return .claude
        }
    }
}

/// Usage window type: primary (5-hour) or secondary (weekly)
enum UsageWindowKind: String, Codable {
    /// Short-term usage window (5 hours)
    case primary
    /// Long-term usage window (7 days)
    case secondary
}

/// Standard usage limit durations in seconds.
/// These values represent the time windows used by AI providers for rate limiting.
enum UsageLimitDuration {
    /// 5-hour window duration in seconds (5 * 60 * 60 = 18,000)
    static let fiveHours: TimeInterval = 5 * 60 * 60
    /// 7-day window duration in seconds (7 * 24 * 60 * 60 = 604,800)
    static let sevenDays: TimeInterval = 7 * 24 * 60 * 60
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
struct UsageSnapshot: Codable, SnapshotData {
    let provider: UsageProvider
    /// When this snapshot was fetched
    let fetchedAt: Date
    /// 5-hour usage window
    let primaryWindow: UsageWindow?
    /// Weekly usage window
    let secondaryWindow: UsageWindow?
}

// MARK: - Storage Protocols

/// Protocol for types that can provide a snapshot filename.
/// Implemented by provider enums (UsageProvider, TokenUsageProvider) to determine storage paths.
protocol SnapshotFileNaming {
    /// The filename used for storing snapshots of this provider
    var snapshotFileName: String { get }
}

/// Protocol for snapshot data types that have an associated provider.
/// Implemented by snapshot structs (UsageSnapshot, TokenUsageSnapshot).
protocol SnapshotData: Codable {
    /// The provider type for this snapshot
    associatedtype Provider: SnapshotFileNaming
    /// The provider this snapshot belongs to
    var provider: Provider { get }
}

// MARK: - Storage Errors

/// Errors that can occur when accessing the snapshot store
enum UsageSnapshotStoreError: Error {
    /// App Group container is not accessible
    case appGroupUnavailable
    /// Failed to read snapshot file
    case readFailed(underlying: Error)
    /// Failed to decode snapshot data
    case decodeFailed(underlying: Error)
}

/// Resolves localized error messages for usage snapshot store errors.
enum UsageSnapshotStoreErrorMessageResolver {
    /// Returns a localized message for the given error.
    /// - Parameters:
    ///   - error: The error to describe.
    ///   - localize: Function that resolves a localization key.
    ///   - includeUnderlying: Whether to include underlying error details.
    static func resolveMessage(
        for error: UsageSnapshotStoreError,
        localize: (String) -> String,
        includeUnderlying: Bool
    ) -> String {
        // Choose the base localized message and optionally append underlying error details.
        switch error {
        case .appGroupUnavailable:
            return localize("error.appGroupUnavailable")
        case .readFailed(let underlying):
            return resolveMessageWithUnderlying(
                baseKey: "error.readFailed",
                localize: localize,
                underlying: underlying,
                includeUnderlying: includeUnderlying
            )
        case .decodeFailed(let underlying):
            return resolveMessageWithUnderlying(
                baseKey: "error.decodeFailed",
                localize: localize,
                underlying: underlying,
                includeUnderlying: includeUnderlying
            )
        }
    }

    private static func resolveMessageWithUnderlying(
        baseKey: String,
        localize: (String) -> String,
        underlying: Error,
        includeUnderlying: Bool
    ) -> String {
        // Attach underlying description only when requested.
        let baseMessage = localize(baseKey)
        guard includeUnderlying else { return baseMessage }
        return baseMessage + " (\(underlying.localizedDescription))"
    }
}

// MARK: - Generic Snapshot Store

/// Generic snapshot store for persisting data via App Group shared container.
/// Provides common load/save functionality for any snapshot type.
/// Used as the base implementation for UsageSnapshotStore and TokenUsageSnapshotStore.
class AppGroupSnapshotStore<Provider: SnapshotFileNaming, Snapshot: SnapshotData>
    where Snapshot.Provider == Provider {

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new snapshot store with the specified configuration.
    /// - Parameters:
    ///   - fileManager: File manager for disk operations (default: .default)
    ///   - encoder: JSON encoder for serialization (default: new encoder with date configuration)
    ///   - decoder: JSON decoder for deserialization (default: new decoder with date configuration)
    init(
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        // Use consistent ISO8601 encoding/decoding across all snapshots.
        DateCodec.configureEncoder(self.encoder)
        DateCodec.configureDecoder(self.decoder)
    }

    /// Returns true if the App Group container is accessible
    var isAppGroupAvailable: Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId) != nil
    }

    /// Loads a snapshot for the specified provider from disk.
    /// Returns nil if loading fails for any reason.
    /// - Parameter provider: The provider to load snapshot for
    /// - Returns: The loaded snapshot, or nil if not found or failed to load
    func loadSnapshot(for provider: Provider) -> Snapshot? {
        // Ignore errors for a non-throwing convenience path.
        try? tryLoadSnapshot(for: provider)
    }

    /// Loads a snapshot for the specified provider from disk with detailed error information.
    /// Use this method when you need to handle specific error cases.
    /// - Parameter provider: The provider to load snapshot for
    /// - Returns: The loaded snapshot
    /// - Throws: `UsageSnapshotStoreError` if loading fails
    func tryLoadSnapshot(for provider: Provider) throws -> Snapshot {
        // Resolve the storage path in the App Group container.
        guard let url = snapshotFileURL(for: provider) else {
            throw UsageSnapshotStoreError.appGroupUnavailable
        }
        // Read and decode the snapshot from disk.
        return try withSecurityScopedAccess(url) {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw UsageSnapshotStoreError.readFailed(underlying: error)
            }
            do {
                return try decoder.decode(Snapshot.self, from: data)
            } catch {
                throw UsageSnapshotStoreError.decodeFailed(underlying: error)
            }
        }
    }

    /// Saves a snapshot to disk for later retrieval by widgets
    /// - Parameter snapshot: The snapshot to save
    /// - Throws: `UsageSnapshotStoreError` if saving fails
    func saveSnapshot(_ snapshot: Snapshot) throws {
        // Resolve the storage path and ensure the directory exists.
        guard let url = snapshotFileURL(for: snapshot.provider, createDirectory: true) else {
            throw UsageSnapshotStoreError.appGroupUnavailable
        }
        // Encode then persist atomically to avoid partial writes.
        let data = try encoder.encode(snapshot)
        try withSecurityScopedAccess(url) {
            try data.write(to: url, options: .atomic)
        }
    }

    /// Returns the file URL for the snapshot of the given provider.
    /// - Parameters:
    ///   - provider: The provider whose snapshot URL to return
    ///   - createDirectory: Whether to create the directory if it doesn't exist
    /// - Returns: The file URL, or nil if App Group is unavailable
    private func snapshotFileURL(for provider: Provider, createDirectory: Bool = false) -> URL? {
        // Locate the App Group container directory.
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else { return nil }
        let directoryURL = containerURL.appendingPathComponent(
            AppGroupConfig.snapshotDirectory, isDirectory: true
        )
        // Create the snapshots directory on demand for write operations.
        if createDirectory {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent(provider.snapshotFileName)
    }

    /// Executes an action with security-scoped resource access.
    /// Required for sandboxed apps accessing App Group containers.
    /// - Parameters:
    ///   - url: The URL to access
    ///   - action: The action to perform with access
    /// - Returns: The result of the action
    private func withSecurityScopedAccess<T>(_ url: URL, _ action: () throws -> T) rethrows -> T {
        // Temporarily access security-scoped resources for sandboxed App Group access.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try action()
    }
}

/// Persists and retrieves usage snapshots via App Group shared container.
/// Used by both the main app (for writing) and widgets (for reading).
/// Inherits common functionality from AppGroupSnapshotStore.
final class UsageSnapshotStore: AppGroupSnapshotStore<UsageProvider, UsageSnapshot> {
    /// Shared singleton instance for app-wide use
    static let shared = UsageSnapshotStore()
}
