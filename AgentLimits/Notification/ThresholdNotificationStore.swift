// MARK: - ThresholdNotificationStore.swift
// Persists threshold notification settings to UserDefaults.
// Follows the same pattern as WakeUpScheduleStore.

import Foundation
import OSLog

// MARK: - Threshold Notification Store

/// Persists threshold notification settings to UserDefaults
final class ThresholdNotificationStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "threshold_notification_settings"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        DateCodec.configureEncoder(encoder)
        DateCodec.configureDecoder(decoder)
    }

    /// Loads all settings from storage
    func loadSettings() -> [UsageProvider: ProviderThresholdSettings] {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? decoder.decode([ProviderThresholdSettings].self, from: data) else {
            Logger.notification.info("ThresholdNotificationStore: No saved settings, returning defaults")
            return makeDefaultSettings()
        }
        let result = Dictionary(uniqueKeysWithValues: settings.map { ($0.provider, $0) })
        for (provider, providerSettings) in result {
            let primaryWarningLastNotified = providerSettings.primaryWindow.warning.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            let primaryDangerLastNotified = providerSettings.primaryWindow.danger.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            let secondaryWarningLastNotified = providerSettings.secondaryWindow.warning.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            let secondaryDangerLastNotified = providerSettings.secondaryWindow.danger.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            Logger.notification.debug("ThresholdNotificationStore: Loaded \(provider.rawValue) primary.warning.lastNotified=\(primaryWarningLastNotified) primary.danger.lastNotified=\(primaryDangerLastNotified) secondary.warning.lastNotified=\(secondaryWarningLastNotified) secondary.danger.lastNotified=\(secondaryDangerLastNotified)")
        }
        return result
    }

    /// Saves all settings to storage
    func saveSettings(_ settings: [UsageProvider: ProviderThresholdSettings]) {
        let array = Array(settings.values)
        if let data = try? encoder.encode(array) {
            userDefaults.set(data, forKey: key)
        }
    }

    /// Updates lastNotifiedResetAt for a specific window
    func updateLastNotifiedResetAt(
        for provider: UsageProvider,
        windowKind: UsageWindowKind,
        level: UsageThresholdLevel,
        resetAt: Date
    ) {
        var settings = loadSettings()
        guard var providerSettings = settings[provider] else {
            Logger.notification.warning("ThresholdNotificationStore: Provider settings not found for \(provider.rawValue)")
            return
        }

        switch (windowKind, level) {
        case (.primary, .warning):
            providerSettings.primaryWindow.warning.lastNotifiedResetAt = resetAt
        case (.primary, .danger):
            providerSettings.primaryWindow.danger.lastNotifiedResetAt = resetAt
        case (.secondary, .warning):
            providerSettings.secondaryWindow.warning.lastNotifiedResetAt = resetAt
        case (.secondary, .danger):
            providerSettings.secondaryWindow.danger.lastNotifiedResetAt = resetAt
        }

        settings[provider] = providerSettings
        saveSettings(settings)
        Logger.notification.debug("ThresholdNotificationStore: Saved lastNotifiedResetAt=\(Int(resetAt.timeIntervalSince1970)) for \(provider.rawValue) \(windowKind.rawValue) \(level.rawValue)")
    }

    /// Creates default settings for all providers
    private func makeDefaultSettings() -> [UsageProvider: ProviderThresholdSettings] {
        Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map {
            ($0, ProviderThresholdSettings.defaultSettings(for: $0))
        })
    }
}
