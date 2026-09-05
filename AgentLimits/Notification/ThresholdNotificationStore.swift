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
    private let version2Key = "threshold_notification_settings_v2"
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
        var result = Dictionary(uniqueKeysWithValues: settings.map { ($0.provider, $0) })
        // Fill in defaults for any newly added providers not yet in persisted data.
        for provider in UsageProvider.allCases where result[provider] == nil {
            result[provider] = ProviderThresholdSettings.defaultSettings(for: provider)
        }
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

    /// 動的サービス対応のversion 2設定を読み込み、初回は旧設定から移行します。
    func loadServiceSettings() -> [UsageServiceKey: ServiceThresholdSettings] {
        if let data = userDefaults.data(forKey: version2Key),
           let values = try? decoder.decode([ServiceThresholdSettings].self, from: data) {
            return Dictionary(uniqueKeysWithValues: values.map { ($0.serviceKey, $0) })
        }
        let migrated = migrateLegacySettings(loadSettings())
        saveServiceSettings(migrated)
        return migrated
    }

    /// version 2通知設定を保存します。
    func saveServiceSettings(_ settings: [UsageServiceKey: ServiceThresholdSettings]) {
        if let data = try? encoder.encode(Array(settings.values)) {
            userDefaults.set(data, forKey: version2Key)
        }
    }

    /// 動的サービスの通知済み状態を更新します。
    func updateNotificationState(
        for serviceKey: UsageServiceKey,
        windowKind: SemanticUsageWindowKind,
        level: UsageThresholdLevel,
        resetAt: Date?,
        isThresholdCurrentlyExceeded: Bool
    ) {
        var allSettings = loadServiceSettings()
        var serviceSettings = allSettings[serviceKey] ?? .defaultSettings(
            for: serviceKey,
            windowKinds: [windowKind]
        )
        var windowSettings = serviceSettings.settings(for: windowKind)
        switch level {
        case .warning:
            windowSettings.warning.lastNotifiedResetAt = resetAt
            windowSettings.warning.isThresholdCurrentlyExceeded = isThresholdCurrentlyExceeded
        case .danger:
            windowSettings.danger.lastNotifiedResetAt = resetAt
            windowSettings.danger.isThresholdCurrentlyExceeded = isThresholdCurrentlyExceeded
        }
        serviceSettings.windows[windowKind] = windowSettings
        allSettings[serviceKey] = serviceSettings
        saveServiceSettings(allSettings)
    }

    /// 期限なし利用枠で使う通知済み状態だけを解除します。
    func clearNoResetNotificationState(
        for serviceKey: UsageServiceKey,
        windowKind: SemanticUsageWindowKind,
        level: UsageThresholdLevel
    ) {
        var allSettings = loadServiceSettings()
        guard var serviceSettings = allSettings[serviceKey] else { return }
        var windowSettings = serviceSettings.settings(for: windowKind)
        switch level {
        case .warning: windowSettings.warning.isThresholdCurrentlyExceeded = false
        case .danger: windowSettings.danger.isThresholdCurrentlyExceeded = false
        }
        serviceSettings.windows[windowKind] = windowSettings
        allSettings[serviceKey] = serviceSettings
        saveServiceSettings(allSettings)
    }

    /// 削除されたサービスのversion 2通知設定を削除します。
    func deleteServiceSettings(for serviceKey: UsageServiceKey) {
        var allSettings = loadServiceSettings()
        allSettings.removeValue(forKey: serviceKey)
        saveServiceSettings(allSettings)
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

    private func migrateLegacySettings(
        _ legacy: [UsageProvider: ProviderThresholdSettings]
    ) -> [UsageServiceKey: ServiceThresholdSettings] {
        Dictionary(uniqueKeysWithValues: legacy.map { provider, settings in
            let windows: [SemanticUsageWindowKind: WindowThresholdSettings]
            if provider == .githubCopilot {
                windows = [.oneMonth: settings.primaryWindow]
            } else {
                windows = [
                    .fiveHours: settings.primaryWindow,
                    .oneWeek: settings.secondaryWindow,
                ]
            }
            let serviceKey = UsageServiceKey.builtIn(provider)
            return (serviceKey, ServiceThresholdSettings(serviceKey: serviceKey, windows: windows))
        })
    }
}
