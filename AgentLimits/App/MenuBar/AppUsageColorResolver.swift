// MARK: - AppUsageColorResolver.swift
// アプリターゲット用の使用率カラーリゾルバー。
// AgentLimitsWidget の WidgetUsageColorResolver と同等のロジックをアプリ側でも使えるように提供する。

import SwiftUI

/// 使用率に応じたメニュー側の色を解決するユーティリティ。
enum AppUsageColorResolver {
    /// 使用率テキスト用のステータス色（緑/オレンジ/赤）を返す。
    static func statusColor(
        for window: UsageWindow?,
        provider: UsageProvider,
        windowKind: UsageWindowKind
    ) -> Color {
        guard let window else { return .secondary }
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        let level = UsageStatusLevelResolver.level(
            for: window.usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
        return statusColor(for: level)
    }

    /// バーのメインカラー判定（ウィジェット同等）。`donutUseStatus` が ON のときのみ閾値超過レベルを返す。
    static func barLevel(
        usedPercent: Double?,
        provider: UsageProvider,
        windowKind: UsageWindowKind
    ) -> UsageStatusLevel? {
        let defaults = AppGroupDefaults.shared
        let useStatusColor = defaults?.bool(forKey: UsageColorKeys.donutUseStatus) ?? false
        guard useStatusColor, let usedPercent else { return nil }
        let thresholds = UsageStatusThresholdStore.loadThresholds(for: provider, windowKind: windowKind)
        return UsageStatusLevelResolver.level(
            for: usedPercent,
            isRemainingMode: false,
            warningThreshold: thresholds.warningPercent,
            dangerThreshold: thresholds.dangerPercent
        )
    }

    /// 使用率バーのメインカラー（ドーナツリングの外輪と同じ規則）。
    static func barColor(
        usedPercent: Double?,
        provider: UsageProvider,
        windowKind: UsageWindowKind
    ) -> Color {
        if let level = barLevel(usedPercent: usedPercent, provider: provider, windowKind: windowKind) {
            return statusColor(for: level)
        }
        return resolveStoredColor(for: UsageColorKeys.donut, defaultColor: .accentColor)
    }

    private static func statusColor(for level: UsageStatusLevel) -> Color {
        switch level {
        case .green:
            return resolveStoredColor(for: UsageColorKeys.statusGreen, defaultColor: .green)
        case .orange:
            return resolveStoredColor(for: UsageColorKeys.statusOrange, defaultColor: .orange)
        case .red:
            return resolveStoredColor(for: UsageColorKeys.statusRed, defaultColor: .red)
        }
    }

    private static func resolveStoredColor(for key: String, defaultColor: Color) -> Color {
        let defaults = AppGroupDefaults.shared
        let storedValue = defaults?.string(forKey: key)
        return ColorHexCodec.resolveColor(from: storedValue, defaultColor: defaultColor)
    }
}
