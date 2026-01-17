// MARK: - AppUsageModels.swift
// UI-facing usage display helpers and UserDefaults keys.
// Handles percent conversion between "used" and "remaining" modes and
// provides snapshot helpers for toggling display modes.

import Foundation

/// Keys used for persisting small app preferences in UserDefaults
enum UserDefaultsKeys {
    static let displayMode = SharedUserDefaultsKeys.displayMode
    static let cachedDisplayMode = SharedUserDefaultsKeys.cachedDisplayMode
    static let menuBarStatusCodexEnabled = "menu_bar_status_codex_enabled"
    static let menuBarStatusClaudeEnabled = "menu_bar_status_claude_enabled"
}

/// Display mode for usage percent: used vs remaining
enum UsageDisplayMode: String, Codable, CaseIterable, Identifiable {
    case used
    case remaining
    case ideal
    case usedWithIdeal

    var id: String { rawValue }

    /// Localized display name resolved via `Localizable.strings`
    var localizedDisplayName: String {
        switch self {
        case .used:
            return "displayMode.used".localized()
        case .remaining:
            return "displayMode.remaining".localized()
        case .ideal:
            return "displayMode.ideal".localized()
        case .usedWithIdeal:
            return "displayMode.usedWithIdeal".localized()
        }
    }

    /// Converts a used-percent value into the current display mode's value
    func displayPercent(from usedPercent: Double) -> Double {
        convertPercent(usedPercent, from: .used)
    }

    /// Converts a used-percent value into the current display mode's value with optional window for ideal calculation
    func displayPercent(from usedPercent: Double, window: UsageWindow?) -> Double {
        switch self {
        case .used, .usedWithIdeal:
            return max(0, min(100, usedPercent))
        case .remaining:
            return max(0, min(100, 100 - usedPercent))
        case .ideal:
            return window?.calculateIdealUsagePercent() ?? 0
        }
    }

    /// Converts a percentage from a source mode to a target mode (clamped 0-100)
    func convertPercent(_ percent: Double, from sourceMode: UsageDisplayMode) -> Double {
        let value: Double
        if sourceMode == self {
            value = percent
        } else if self == .ideal || self == .usedWithIdeal {
            // Ideal mode doesn't convert from other modes
            value = percent
        } else if sourceMode == .ideal || sourceMode == .usedWithIdeal {
            // Converting from ideal to used/remaining doesn't make sense
            value = percent
        } else {
            value = 100 - percent
        }
        return max(0, min(100, value))
    }
}

extension UsageDisplayMode {
    /// Maps app display mode to the shared raw mode stored in snapshots.
    func makeDisplayModeRaw() -> UsageDisplayModeRaw {
        switch self {
        case .used:
            return .used
        case .remaining:
            return .remaining
        case .ideal:
            return .ideal
        case .usedWithIdeal:
            return .usedWithIdeal
        }
    }
}

extension UsageDisplayModeRaw {
    /// Maps a shared raw mode to the app display mode.
    func makeDisplayMode() -> UsageDisplayMode {
        switch self {
        case .used:
            return .used
        case .remaining:
            return .remaining
        case .ideal:
            return .ideal
        case .usedWithIdeal:
            return .usedWithIdeal
        }
    }
}

extension UsageSnapshot {
    /// Returns a copy with the display mode updated (used percent remains intact).
    func makeSnapshot(for displayMode: UsageDisplayMode) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            fetchedAt: fetchedAt,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            displayMode: displayMode.makeDisplayModeRaw()
        )
    }
}

extension UsageSnapshotStoreError: LocalizedError {
    /// User-friendly localized description for snapshot store errors.
    /// Provides localized error messages for app display.
    var errorDescription: String? {
        UsageSnapshotStoreErrorMessageResolver.resolveMessage(
            for: self,
            localize: { $0.localized() },
            includeUnderlying: true
        )
    }
}
