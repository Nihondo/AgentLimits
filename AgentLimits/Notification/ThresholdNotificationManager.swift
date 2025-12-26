// MARK: - ThresholdNotificationManager.swift
// Manages threshold notifications for usage limits.
// Checks usage against thresholds and sends system notifications.

import Combine
import Foundation
import UserNotifications

// MARK: - Notification Identifiers

/// Identifiers for threshold notifications
private enum NotificationIdentifier {
    static func makeId(provider: UsageProvider, windowKind: UsageWindowKind) -> String {
        "threshold-\(provider.rawValue)-\(windowKind.rawValue)"
    }
}

// MARK: - Threshold Notification Manager

/// Manages usage threshold notifications
@MainActor
final class ThresholdNotificationManager: ObservableObject {
    static let shared = ThresholdNotificationManager()

    @Published private(set) var settings: [UsageProvider: ProviderThresholdSettings]
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
        self.settings = useStore.loadSettings()

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
            NSLog("ThresholdNotificationManager: Authorization request failed: %@", error.localizedDescription)
            isNotificationAuthorized = false
            return false
        }
    }

    // MARK: - Settings Management

    /// Updates settings for a provider
    /// Resets lastNotifiedResetAt if threshold is changed (to allow re-notification)
    func updateSettings(_ providerSettings: ProviderThresholdSettings) {
        var updatedSettings = providerSettings

        // Check if threshold changed and reset lastNotifiedResetAt if so
        if let oldSettings = settings[providerSettings.provider] {
            // Primary window: reset if threshold changed
            if oldSettings.primaryWindow.thresholdPercent != providerSettings.primaryWindow.thresholdPercent {
                updatedSettings.primaryWindow.lastNotifiedResetAt = nil
            }
            // Secondary window: reset if threshold changed
            if oldSettings.secondaryWindow.thresholdPercent != providerSettings.secondaryWindow.thresholdPercent {
                updatedSettings.secondaryWindow.lastNotifiedResetAt = nil
            }
        }

        settings[providerSettings.provider] = updatedSettings
        store.saveSettings(settings)
    }

    /// Returns settings for a provider
    func getSettings(for provider: UsageProvider) -> ProviderThresholdSettings {
        settings[provider] ?? .defaultSettings(for: provider)
    }

    // MARK: - Threshold Checking

    /// Checks thresholds for a snapshot and sends notifications if needed
    func checkThresholdsIfNeeded(for snapshot: UsageSnapshot) async {
        guard isNotificationAuthorized else { return }

        let providerSettings = getSettings(for: snapshot.provider)

        // Check primary window (5h)
        if let window = snapshot.primaryWindow {
            await checkWindowThreshold(
                provider: snapshot.provider,
                window: window,
                windowSettings: providerSettings.primaryWindow
            )
        }

        // Check secondary window (weekly)
        if let window = snapshot.secondaryWindow {
            await checkWindowThreshold(
                provider: snapshot.provider,
                window: window,
                windowSettings: providerSettings.secondaryWindow
            )
        }
    }

    /// Checks a single window against its threshold
    private func checkWindowThreshold(
        provider: UsageProvider,
        window: UsageWindow,
        windowSettings: WindowThresholdSettings
    ) async {
        // Skip if disabled
        guard windowSettings.isEnabled else { return }

        // Skip if below threshold
        let usedPercent = Int(window.usedPercent)
        guard usedPercent >= windowSettings.thresholdPercent else { return }

        // Skip if already notified for this reset cycle (duplicate prevention)
        // Allow 10 seconds tolerance to handle API returning slightly different timestamps
        if let lastNotified = windowSettings.lastNotifiedResetAt,
           let resetAt = window.resetAt {
            let lastNotifiedSeconds = Int(lastNotified.timeIntervalSince1970)
            let resetAtSeconds = Int(resetAt.timeIntervalSince1970)
            let diff = abs(lastNotifiedSeconds - resetAtSeconds)
            NSLog("ThresholdNotificationManager: %@ %@ lastNotified=%d resetAt=%d diff=%d",
                  provider.displayName, window.kind.rawValue, lastNotifiedSeconds, resetAtSeconds, diff)
            if diff <= 10 {
                NSLog("ThresholdNotificationManager: Skipping duplicate notification (within 10s tolerance)")
                return
            }
        } else {
            NSLog("ThresholdNotificationManager: %@ %@ lastNotified=%@ resetAt=%@",
                  provider.displayName, window.kind.rawValue,
                  windowSettings.lastNotifiedResetAt?.description ?? "nil",
                  window.resetAt?.description ?? "nil")
        }

        // Send notification
        await sendNotification(
            provider: provider,
            windowKind: window.kind,
            usedPercent: usedPercent,
            thresholdPercent: windowSettings.thresholdPercent
        )

        // Update lastNotifiedResetAt to prevent duplicates
        if let resetAt = window.resetAt {
            store.updateLastNotifiedResetAt(
                for: provider,
                windowKind: window.kind,
                resetAt: resetAt
            )
            // Reload settings to update published property
            settings = store.loadSettings()
        }
    }

    /// Sends a notification for threshold exceeded
    private func sendNotification(
        provider: UsageProvider,
        windowKind: UsageWindowKind,
        usedPercent: Int,
        thresholdPercent: Int
    ) async {
        let content = UNMutableNotificationContent()

        // Title: "Codex 使用量警告" or "Claude Code 使用量警告"
        content.title = String(
            format: "notification.alertTitle".localized(),
            provider.displayName
        )

        // Body: window-specific message
        let bodyKey = windowKind == .primary ? "notification.alertBody5h" : "notification.alertBodyWeek"
        content.body = String(format: bodyKey.localized(), usedPercent)

        content.sound = .default

        let identifier = NotificationIdentifier.makeId(provider: provider, windowKind: windowKind)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await notificationCenter.add(request)
            NSLog(
                "ThresholdNotificationManager: Sent notification for %@ %@ at %d%%",
                provider.displayName,
                windowKind.rawValue,
                usedPercent
            )
        } catch {
            NSLog(
                "ThresholdNotificationManager: Failed to send notification: %@",
                error.localizedDescription
            )
        }
    }

    // MARK: - Testing Support

    /// For testing: reloads settings from store
    func reloadSettings() {
        settings = store.loadSettings()
    }
}
