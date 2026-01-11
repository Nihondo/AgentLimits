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

    var id: String { rawValue }

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

extension UsageDisplayMode {
    /// Maps app display mode to the shared raw mode stored in snapshots.
    func makeDisplayModeRaw() -> UsageDisplayModeRaw {
        switch self {
        case .used:
            return .used
        case .remaining:
            return .remaining
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
