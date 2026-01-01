// MARK: - ThresholdNotificationSettings.swift
// Data models for usage threshold notification settings.
// Defines per-window and per-provider threshold configurations.

import Foundation

// MARK: - Threshold Level Settings

/// Threshold settings for a single notification level (warning/danger)
struct ThresholdLevelSettings: Codable, Equatable {
    /// Whether threshold notification is enabled for this level
    var isEnabled: Bool
    /// Threshold percentage (1-100) that triggers notification
    var thresholdPercent: Int
    /// Reset time of the last notification (for duplicate prevention)
    var lastNotifiedResetAt: Date?

    /// Default settings for warning level
    static func makeWarningSettings() -> ThresholdLevelSettings {
        ThresholdLevelSettings(
            isEnabled: true,
            thresholdPercent: 70,
            lastNotifiedResetAt: nil
        )
    }

    /// Default settings for danger level
    static func makeDangerSettings() -> ThresholdLevelSettings {
        ThresholdLevelSettings(
            isEnabled: true,
            thresholdPercent: 90,
            lastNotifiedResetAt: nil
        )
    }
}

// MARK: - Window Threshold Settings

/// Threshold settings for a single usage window (5h or weekly)
struct WindowThresholdSettings: Codable, Equatable {
    /// Warning level settings
    var warning: ThresholdLevelSettings
    /// Danger level settings
    var danger: ThresholdLevelSettings

    /// Default settings with 70% warning and 90% danger
    static func defaultSettings() -> WindowThresholdSettings {
        WindowThresholdSettings(
            warning: .makeWarningSettings(),
            danger: .makeDangerSettings()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case warning
        case danger
        case isEnabled
        case thresholdPercent
        case lastNotifiedResetAt
    }

    init(warning: ThresholdLevelSettings, danger: ThresholdLevelSettings) {
        self.warning = warning
        self.danger = danger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.warning) || container.contains(.danger) {
            warning = try container.decode(ThresholdLevelSettings.self, forKey: .warning)
            danger = try container.decode(ThresholdLevelSettings.self, forKey: .danger)
            return
        }

        let isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        let thresholdPercent = try container.decode(Int.self, forKey: .thresholdPercent)
        let lastNotifiedResetAt = try container.decodeIfPresent(Date.self, forKey: .lastNotifiedResetAt)
        let normalizedWarningPercent = 70
        warning = ThresholdLevelSettings(
            isEnabled: isEnabled,
            thresholdPercent: normalizedWarningPercent,
            lastNotifiedResetAt: nil
        )
        danger = ThresholdLevelSettings(
            isEnabled: isEnabled,
            thresholdPercent: max(thresholdPercent, normalizedWarningPercent),
            lastNotifiedResetAt: lastNotifiedResetAt
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(warning, forKey: .warning)
        try container.encode(danger, forKey: .danger)
    }
}

// MARK: - Usage Threshold Level

/// Notification level for usage threshold alerts
enum UsageThresholdLevel: String, Codable, CaseIterable {
    case warning
    case danger
}

// MARK: - Provider Threshold Settings

/// Threshold settings for a specific provider (Codex or Claude)
struct ProviderThresholdSettings: Codable, Equatable {
    /// The provider these settings apply to
    let provider: UsageProvider
    /// Settings for the 5-hour window
    var primaryWindow: WindowThresholdSettings
    /// Settings for the weekly window
    var secondaryWindow: WindowThresholdSettings

    /// Default settings for a provider
    static func defaultSettings(for provider: UsageProvider) -> ProviderThresholdSettings {
        ProviderThresholdSettings(
            provider: provider,
            primaryWindow: .defaultSettings(),
            secondaryWindow: .defaultSettings()
        )
    }
}
