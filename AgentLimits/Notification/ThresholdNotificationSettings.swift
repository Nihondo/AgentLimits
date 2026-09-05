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
    /// 期限がない利用枠で、現在の閾値超過を通知済みかを表します。
    var isThresholdCurrentlyExceeded: Bool

    init(
        isEnabled: Bool,
        thresholdPercent: Int,
        lastNotifiedResetAt: Date?,
        isThresholdCurrentlyExceeded: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.thresholdPercent = thresholdPercent
        self.lastNotifiedResetAt = lastNotifiedResetAt
        self.isThresholdCurrentlyExceeded = isThresholdCurrentlyExceeded
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case thresholdPercent
        case lastNotifiedResetAt
        case isThresholdCurrentlyExceeded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            thresholdPercent: try container.decode(Int.self, forKey: .thresholdPercent),
            lastNotifiedResetAt: try container.decodeIfPresent(Date.self, forKey: .lastNotifiedResetAt),
            isThresholdCurrentlyExceeded: try container.decodeIfPresent(
                Bool.self,
                forKey: .isThresholdCurrentlyExceeded
            ) ?? false
        )
    }

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

// MARK: - Dynamic Service Threshold Settings

/// 組み込み・カスタム共通のサービス単位通知設定です。
struct ServiceThresholdSettings: Codable, Equatable {
    let serviceKey: UsageServiceKey
    var windows: [SemanticUsageWindowKind: WindowThresholdSettings]

    /// 指定利用枠の設定を返し、未設定時は既定値を使用します。
    func settings(for kind: SemanticUsageWindowKind) -> WindowThresholdSettings {
        windows[kind] ?? .defaultSettings()
    }

    static func defaultSettings(
        for serviceKey: UsageServiceKey,
        windowKinds: [SemanticUsageWindowKind]
    ) -> ServiceThresholdSettings {
        ServiceThresholdSettings(
            serviceKey: serviceKey,
            windows: Dictionary(uniqueKeysWithValues: windowKinds.map { ($0, .defaultSettings()) })
        )
    }
}
