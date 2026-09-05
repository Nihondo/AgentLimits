// MARK: - ThresholdNotificationManager.swift
// Manages threshold notifications for usage limits.
// Checks usage against thresholds and sends system notifications.

import Combine
import Foundation
import OSLog
import UserNotifications

// MARK: - Notification Identifiers

/// Identifiers for threshold notifications
private enum NotificationIdentifier {
    static func makeId(provider: UsageProvider, windowKind: UsageWindowKind, level: UsageThresholdLevel) -> String {
        "threshold-\(provider.rawValue)-\(windowKind.rawValue)-\(level.rawValue)"
    }

    static func makeId(
        serviceKey: UsageServiceKey,
        windowKind: SemanticUsageWindowKind,
        level: UsageThresholdLevel
    ) -> String {
        "threshold-v2-\(serviceKey.rawValue)-\(windowKind.rawValue)-\(level.rawValue)"
    }
}

// MARK: - Threshold Notification Manager

/// Manages usage threshold notifications
@MainActor
final class ThresholdNotificationManager: ObservableObject {
    static let shared = ThresholdNotificationManager()

    @Published private(set) var settings: [UsageProvider: ProviderThresholdSettings]
    @Published private(set) var serviceSettings: [UsageServiceKey: ServiceThresholdSettings]
    @Published private(set) var isNotificationAuthorized: Bool = false

    private let store: ThresholdNotificationStore
    private let notificationCenter: UNUserNotificationCenter

    private init(
        store: ThresholdNotificationStore? = nil,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        let useStore = store ?? ThresholdNotificationStore()
        self.store = useStore
        self.notificationCenter = notificationCenter
        let loadedSettings = useStore.loadSettings()
        let sanitizedSettings = Self.sanitizeSettings(loadedSettings)
        if sanitizedSettings != loadedSettings {
            useStore.saveSettings(sanitizedSettings)
        }
        self.settings = sanitizedSettings
        self.serviceSettings = useStore.loadServiceSettings()
        syncUsageStatusThresholds(from: sanitizedSettings)
        syncServiceUsageStatusThresholds()

        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Checks current notification authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isNotificationAuthorized = settings.authorizationStatus == .authorized
    }

    /// Requests notification authorization from user
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isNotificationAuthorized = granted
            return granted
        } catch {
            Logger.notification.error("ThresholdNotificationManager: Authorization request failed: \(error.localizedDescription)")
            isNotificationAuthorized = false
            return false
        }
    }

    // MARK: - Settings Management

    /// Updates settings for a provider
    /// Resets lastNotifiedResetAt if threshold is changed (to allow re-notification)
    func updateSettings(_ providerSettings: ProviderThresholdSettings) {
        var updatedSettings = providerSettings
        updatedSettings.primaryWindow = Self.normalizeWindowSettings(updatedSettings.primaryWindow)
        updatedSettings.secondaryWindow = Self.normalizeWindowSettings(updatedSettings.secondaryWindow)

        // Check if threshold changed and reset lastNotifiedResetAt if so
        if let oldSettings = settings[providerSettings.provider] {
            updatedSettings.primaryWindow.warning = makeResetLevelSettings(
                oldLevel: oldSettings.primaryWindow.warning,
                newLevel: updatedSettings.primaryWindow.warning
            )
            updatedSettings.primaryWindow.danger = makeResetLevelSettings(
                oldLevel: oldSettings.primaryWindow.danger,
                newLevel: updatedSettings.primaryWindow.danger
            )
            updatedSettings.secondaryWindow.warning = makeResetLevelSettings(
                oldLevel: oldSettings.secondaryWindow.warning,
                newLevel: updatedSettings.secondaryWindow.warning
            )
            updatedSettings.secondaryWindow.danger = makeResetLevelSettings(
                oldLevel: oldSettings.secondaryWindow.danger,
                newLevel: updatedSettings.secondaryWindow.danger
            )
        }

        settings[providerSettings.provider] = updatedSettings
        store.saveSettings(settings)
        syncUsageStatusThresholds(from: settings)
        syncLegacyProviderToServiceSettings(updatedSettings)
    }

    /// Returns settings for a provider
    func getSettings(for provider: UsageProvider) -> ProviderThresholdSettings {
        settings[provider] ?? .defaultSettings(for: provider)
    }

    /// Resets settings for a provider to defaults
    func resetSettings(for provider: UsageProvider) {
        let defaultSettings = ProviderThresholdSettings.defaultSettings(for: provider)
        settings[provider] = defaultSettings
        store.saveSettings(settings)
        syncUsageStatusThresholds(from: settings)
        syncLegacyProviderToServiceSettings(defaultSettings)
    }

    /// 共通サービスの指定利用枠設定を返します。
    func getSettings(
        for serviceKey: UsageServiceKey,
        windowKind: SemanticUsageWindowKind
    ) -> WindowThresholdSettings {
        serviceSettings[serviceKey]?.settings(for: windowKind) ?? .defaultSettings()
    }

    /// 共通サービスの指定利用枠設定を更新します。
    func updateSettings(
        _ newSettings: WindowThresholdSettings,
        for serviceKey: UsageServiceKey,
        windowKind: SemanticUsageWindowKind
    ) {
        var normalized = Self.normalizeWindowSettings(newSettings)
        let oldSettings = getSettings(for: serviceKey, windowKind: windowKind)
        normalized.warning = makeResetLevelSettings(
            oldLevel: oldSettings.warning,
            newLevel: normalized.warning
        )
        normalized.danger = makeResetLevelSettings(
            oldLevel: oldSettings.danger,
            newLevel: normalized.danger
        )
        var service = serviceSettings[serviceKey] ?? .defaultSettings(
            for: serviceKey,
            windowKinds: [windowKind]
        )
        service.windows[windowKind] = normalized
        serviceSettings[serviceKey] = service
        store.saveServiceSettings(serviceSettings)
        syncServiceUsageStatusThresholds()
    }

    /// 共通サービスの通知設定を既定値へ戻します。
    func resetSettings(
        for serviceKey: UsageServiceKey,
        windowKinds: [SemanticUsageWindowKind]
    ) {
        serviceSettings[serviceKey] = .defaultSettings(
            for: serviceKey,
            windowKinds: windowKinds
        )
        store.saveServiceSettings(serviceSettings)
        syncServiceUsageStatusThresholds()
    }

    /// 削除されたカスタムサービスの通知設定を除去します。
    func deleteSettings(for serviceKey: UsageServiceKey) {
        serviceSettings.removeValue(forKey: serviceKey)
        store.deleteServiceSettings(for: serviceKey)
        UsageStatusThresholdStore.removeThresholds(for: serviceKey)
        syncServiceUsageStatusThresholds()
    }

    // MARK: - Threshold Checking

    /// 新しい共通スナップショットの利用枠を通知設定へ登録します。
    func registerSnapshot(_ snapshot: UsagePresentationSnapshot) {
        ensureSettingsExist(for: snapshot)
    }

    /// Checks thresholds for a snapshot and sends notifications if needed
    func checkThresholdsIfNeeded(for snapshot: UsageSnapshot) async {
        await checkThresholdsIfNeeded(for: UsagePresentationSnapshot(builtIn: snapshot))
    }

    /// 共通表示スナップショットの各利用枠を通知閾値と比較します。
    func checkThresholdsIfNeeded(for snapshot: UsagePresentationSnapshot) async {
        guard isNotificationAuthorized else { return }

        ensureSettingsExist(for: snapshot)
        for window in snapshot.windows {
            let windowSettings = getSettings(for: snapshot.serviceKey, windowKind: window.kind)
            await checkSemanticWindowThreshold(
                snapshot: snapshot,
                window: window,
                level: .warning,
                levelSettings: windowSettings.warning
            )
            await checkSemanticWindowThreshold(
                snapshot: snapshot,
                window: window,
                level: .danger,
                levelSettings: windowSettings.danger
            )
        }
    }

    private func checkSemanticWindowThreshold(
        snapshot: UsagePresentationSnapshot,
        window: SemanticUsageWindow,
        level: UsageThresholdLevel,
        levelSettings: ThresholdLevelSettings
    ) async {
        guard levelSettings.isEnabled else { return }

        let isThresholdExceeded = Int(window.usedPercent) >= levelSettings.thresholdPercent
        guard isThresholdExceeded else {
            if window.resetAt == nil, levelSettings.isThresholdCurrentlyExceeded {
                store.updateNotificationState(
                    for: snapshot.serviceKey,
                    windowKind: window.kind,
                    level: level,
                    resetAt: nil,
                    isThresholdCurrentlyExceeded: false
                )
                serviceSettings = store.loadServiceSettings()
            }
            return
        }

        if window.resetAt != nil, levelSettings.isThresholdCurrentlyExceeded {
            store.clearNoResetNotificationState(
                for: snapshot.serviceKey,
                windowKind: window.kind,
                level: level
            )
            serviceSettings = store.loadServiceSettings()
        }
        if let resetAt = window.resetAt,
           let lastNotified = levelSettings.lastNotifiedResetAt,
           abs(lastNotified.timeIntervalSince(resetAt)) <= 10 {
            return
        }
        if window.resetAt == nil, levelSettings.isThresholdCurrentlyExceeded {
            return
        }

        let didSend = await sendSemanticNotification(
            serviceKey: snapshot.serviceKey,
            displayName: snapshot.displayName,
            windowKind: window.kind,
            windowLabel: window.displayLabel,
            hasCustomLabel: window.hasCustomLabel,
            level: level,
            usedPercent: Int(window.usedPercent)
        )
        guard didSend else { return }
        store.updateNotificationState(
            for: snapshot.serviceKey,
            windowKind: window.kind,
            level: level,
            resetAt: window.resetAt,
            isThresholdCurrentlyExceeded: window.resetAt == nil
        )
        serviceSettings = store.loadServiceSettings()
    }

    private func sendSemanticNotification(
        serviceKey: UsageServiceKey,
        displayName: String,
        windowKind: SemanticUsageWindowKind,
        windowLabel: String,
        hasCustomLabel: Bool,
        level: UsageThresholdLevel,
        usedPercent: Int
    ) async -> Bool {
        let content = UNMutableNotificationContent()
        let titleKey = level == .warning
            ? "notification.alertTitleWarning"
            : "notification.alertTitleDanger"
        content.title = String(format: titleKey.localized(), displayName)
        if hasCustomLabel {
            content.body = String(
                format: "notification.alertBodyCustom".localized(),
                windowLabel,
                usedPercent
            )
        } else {
            let bodyKey: String
            switch windowKind {
            case .fiveHours: bodyKey = "notification.alertBody5h"
            case .oneWeek: bodyKey = "notification.alertBodyWeek"
            case .oneMonth: bodyKey = "notification.alertBodyMonth"
            }
            content.body = String(format: bodyKey.localized(), usedPercent)
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.makeId(
                serviceKey: serviceKey,
                windowKind: windowKind,
                level: level
            ),
            content: content,
            trigger: nil
        )
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            Logger.notification.error("Failed to send custom threshold notification: \(error.localizedDescription)")
            return false
        }
    }

    private func makeResetLevelSettings(
        oldLevel: ThresholdLevelSettings,
        newLevel: ThresholdLevelSettings
    ) -> ThresholdLevelSettings {
        guard shouldResetNotification(oldLevel: oldLevel, newLevel: newLevel) else { return newLevel }
        var updated = newLevel
        updated.lastNotifiedResetAt = nil
        updated.isThresholdCurrentlyExceeded = false
        return updated
    }

    private func shouldResetNotification(
        oldLevel: ThresholdLevelSettings,
        newLevel: ThresholdLevelSettings
    ) -> Bool {
        if oldLevel.thresholdPercent != newLevel.thresholdPercent {
            return true
        }
        if oldLevel.isEnabled == false && newLevel.isEnabled {
            return true
        }
        return false
    }

    private static func sanitizeSettings(
        _ settings: [UsageProvider: ProviderThresholdSettings]
    ) -> [UsageProvider: ProviderThresholdSettings] {
        Dictionary(uniqueKeysWithValues: settings.map { provider, providerSettings in
            if isValidProviderSettings(providerSettings, provider: provider) {
                return (provider, providerSettings)
            }
            return (provider, ProviderThresholdSettings.defaultSettings(for: provider))
        })
    }

    private static func normalizeWindowSettings(_ settings: WindowThresholdSettings) -> WindowThresholdSettings {
        var updated = settings
        let warningPercent = clampPercent(updated.warning.thresholdPercent)
        let dangerPercent = clampPercent(updated.danger.thresholdPercent)
        updated.warning.thresholdPercent = warningPercent
        updated.danger.thresholdPercent = dangerPercent
        return updated
    }

    private static func clampPercent(_ value: Int) -> Int {
        min(max(value, 1), 100)
    }

    private func syncUsageStatusThresholds(from settings: [UsageProvider: ProviderThresholdSettings]) {
        for (provider, providerSettings) in settings {
            let primaryThresholds = makeUsageStatusThresholds(from: providerSettings.primaryWindow)
            UsageStatusThresholdStore.saveThresholds(primaryThresholds, for: provider, windowKind: .primary)
            let secondaryThresholds = makeUsageStatusThresholds(from: providerSettings.secondaryWindow)
            UsageStatusThresholdStore.saveThresholds(secondaryThresholds, for: provider, windowKind: .secondary)
        }
        UsageStatusThresholdStore.bumpRevision()
    }

    private func ensureSettingsExist(for snapshot: UsagePresentationSnapshot) {
        var service = serviceSettings[snapshot.serviceKey] ?? .defaultSettings(
            for: snapshot.serviceKey,
            windowKinds: snapshot.windows.map(\.kind)
        )
        var changed = serviceSettings[snapshot.serviceKey] == nil
        for window in snapshot.windows where service.windows[window.kind] == nil {
            service.windows[window.kind] = .defaultSettings()
            changed = true
        }
        guard changed else { return }
        serviceSettings[snapshot.serviceKey] = service
        store.saveServiceSettings(serviceSettings)
        syncServiceUsageStatusThresholds()
    }

    private func syncLegacyProviderToServiceSettings(_ legacy: ProviderThresholdSettings) {
        let serviceKey = UsageServiceKey.builtIn(legacy.provider)
        let windows: [SemanticUsageWindowKind: WindowThresholdSettings]
        if legacy.provider == .githubCopilot {
            windows = [.oneMonth: legacy.primaryWindow]
        } else {
            windows = [.fiveHours: legacy.primaryWindow, .oneWeek: legacy.secondaryWindow]
        }
        serviceSettings[serviceKey] = ServiceThresholdSettings(serviceKey: serviceKey, windows: windows)
        store.saveServiceSettings(serviceSettings)
        syncServiceUsageStatusThresholds()
    }

    private func syncServiceUsageStatusThresholds() {
        for (serviceKey, service) in serviceSettings {
            for (windowKind, settings) in service.windows {
                UsageStatusThresholdStore.saveThresholds(
                    makeUsageStatusThresholds(from: settings),
                    for: serviceKey,
                    windowKind: windowKind
                )
            }
        }
        UsageStatusThresholdStore.bumpRevision()
    }

    private func makeUsageStatusThresholds(from settings: WindowThresholdSettings) -> UsageStatusThresholds {
        let warningPercent = Self.clampPercent(settings.warning.thresholdPercent)
        let dangerPercent = Self.clampPercent(settings.danger.thresholdPercent)
        return UsageStatusThresholds(warningPercent: warningPercent, dangerPercent: dangerPercent)
    }

    private static func isValidProviderSettings(
        _ settings: ProviderThresholdSettings,
        provider: UsageProvider
    ) -> Bool {
        guard settings.provider == provider else { return false }
        return isValidWindowSettings(settings.primaryWindow)
            && isValidWindowSettings(settings.secondaryWindow)
    }

    private static func isValidWindowSettings(_ settings: WindowThresholdSettings) -> Bool {
        guard isValidLevelSettings(settings.warning) else { return false }
        guard isValidLevelSettings(settings.danger) else { return false }
        return settings.warning.thresholdPercent <= settings.danger.thresholdPercent
    }

    private static func isValidLevelSettings(_ settings: ThresholdLevelSettings) -> Bool {
        (1...100).contains(settings.thresholdPercent)
    }

    // MARK: - Testing Support

    /// For testing: reloads settings from store
    func reloadSettings() {
        settings = store.loadSettings()
        serviceSettings = store.loadServiceSettings()
    }
}
