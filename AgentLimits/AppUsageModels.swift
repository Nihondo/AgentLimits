// MARK: - AppUsageModels.swift
// UI-facing usage display helpers and UserDefaults keys.
// Handles percent conversion between "used" and "remaining" modes and
// provides snapshot/window helpers for toggling display modes.

import Foundation

/// Keys used for persisting small app preferences in UserDefaults
enum UserDefaultsKeys {
    static let displayMode = "usage_display_mode"
    static let cachedDisplayMode = "usage_display_mode_cached"
}

/// Display mode for usage percent: used vs remaining
enum UsageDisplayMode: String, Codable, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }

    /// Short display name (Japanese for in-app picker)
    var displayName: String {
        switch self {
        case .used:
            return "使用"
        case .remaining:
            return "残り"
        }
    }

    /// Localized display name resolved via `Localizable.strings`
    var localizedDisplayName: String {
        switch self {
        case .used:
            return "displayMode.used".localized()
        case .remaining:
            return "displayMode.remaining".localized()
        }
    }

    /// Converts a used-percent value into the current display mode's value
    func displayPercent(from usedPercent: Double) -> Double {
        convertPercent(usedPercent, from: .used)
    }

    /// Converts a percentage from a source mode to a target mode (clamped 0-100)
    func convertPercent(_ percent: Double, from sourceMode: UsageDisplayMode) -> Double {
        let value: Double
        if sourceMode == self {
            value = percent
        } else {
            value = 100 - percent
        }
        return max(0, min(100, value))
    }
}

extension UsageWindow {
    /// Returns a copy converted to the target display mode (from used)
    func makeWindow(for displayMode: UsageDisplayMode) -> UsageWindow {
        makeWindow(from: .used, to: displayMode)
    }

    /// Returns a copy converted between two display modes
    func makeWindow(from sourceMode: UsageDisplayMode, to targetMode: UsageDisplayMode) -> UsageWindow {
        let displayPercent = targetMode.convertPercent(usedPercent, from: sourceMode)
        return UsageWindow(
            kind: kind,
            usedPercent: displayPercent,
            resetAt: resetAt,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}

extension UsageSnapshot {
    /// Returns a copy converted to the target display mode (from used)
    func makeSnapshot(for displayMode: UsageDisplayMode) -> UsageSnapshot {
        makeSnapshot(from: .used, to: displayMode)
    }

    /// Returns a copy converted between two display modes
    func makeSnapshot(from sourceMode: UsageDisplayMode, to targetMode: UsageDisplayMode) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            fetchedAt: fetchedAt,
            primaryWindow: primaryWindow?.makeWindow(from: sourceMode, to: targetMode),
            secondaryWindow: secondaryWindow?.makeWindow(from: sourceMode, to: targetMode)
        )
    }
}

extension UsageSnapshotStoreError: LocalizedError {
    /// User-friendly localized description for snapshot store errors
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "error.appGroupUnavailable".localized()
        }
    }
}
