// MARK: - ThresholdNotificationSettings.swift
// Data models for usage threshold notification settings.
// Defines per-window and per-provider threshold configurations.

import Foundation

// MARK: - Window Threshold Settings

/// Threshold settings for a single usage window (5h or weekly)
struct WindowThresholdSettings: Codable, Equatable {
    /// Whether threshold notification is enabled for this window
    var isEnabled: Bool
    /// Threshold percentage (1-100) that triggers notification
    var thresholdPercent: Int
    /// Reset time of the last notification (for duplicate prevention)
    var lastNotifiedResetAt: Date?

    /// Default settings with 90% threshold enabled
    static func defaultSettings() -> WindowThresholdSettings {
        WindowThresholdSettings(
            isEnabled: true,
            thresholdPercent: 90,
            lastNotifiedResetAt: nil
        )
    }
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
