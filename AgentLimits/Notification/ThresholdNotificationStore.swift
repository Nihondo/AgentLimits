// MARK: - ThresholdNotificationStore.swift
// Persists threshold notification settings to UserDefaults.
// Follows the same pattern as WakeUpScheduleStore.

import Foundation

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
            NSLog("ThresholdNotificationStore: No saved settings, returning defaults")
            return makeDefaultSettings()
        }
        let result = Dictionary(uniqueKeysWithValues: settings.map { ($0.provider, $0) })
        for (provider, providerSettings) in result {
            let primaryLastNotified = providerSettings.primaryWindow.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            let secondaryLastNotified = providerSettings.secondaryWindow.lastNotifiedResetAt
                .map { Int($0.timeIntervalSince1970) } ?? -1
            NSLog("ThresholdNotificationStore: Loaded %@ primary.lastNotified=%d secondary.lastNotified=%d",
                  provider.rawValue, primaryLastNotified, secondaryLastNotified)
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
        resetAt: Date
    ) {
        var settings = loadSettings()
        guard var providerSettings = settings[provider] else {
            NSLog("ThresholdNotificationStore: Provider settings not found for %@", provider.rawValue)
            return
        }

        switch windowKind {
        case .primary:
            providerSettings.primaryWindow.lastNotifiedResetAt = resetAt
        case .secondary:
            providerSettings.secondaryWindow.lastNotifiedResetAt = resetAt
        }

        settings[provider] = providerSettings
        saveSettings(settings)
        NSLog("ThresholdNotificationStore: Saved lastNotifiedResetAt=%d for %@ %@",
              Int(resetAt.timeIntervalSince1970), provider.rawValue, windowKind.rawValue)
    }

    /// Creates default settings for all providers
    private func makeDefaultSettings() -> [UsageProvider: ProviderThresholdSettings] {
        Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map {
            ($0, ProviderThresholdSettings.defaultSettings(for: $0))
        })
    }
}
