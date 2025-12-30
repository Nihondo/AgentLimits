// MARK: - UsageDisplayModeStore.swift
// Persists display mode preference and rewrites saved snapshots for widgets.
// Ensures widgets and app show consistent percent values across mode changes.

import Foundation
import OSLog
import WidgetKit

/// Manages persisted display mode and rewrites stored snapshots when toggled
final class UsageDisplayModeStore {
    private let store: UsageSnapshotStore
    private let userDefaults: UserDefaults
    private let appGroupDefaults: UserDefaults?

    init(
        store: UsageSnapshotStore = UsageSnapshotStore.shared,
        userDefaults: UserDefaults = .standard,
        appGroupDefaults: UserDefaults? = UserDefaults(suiteName: AppGroupConfig.groupId)
    ) {
        self.store = store
        self.userDefaults = userDefaults
        self.appGroupDefaults = appGroupDefaults
    }

    /// Loads the last persisted display mode (if any)
    func loadCachedDisplayMode() -> UsageDisplayMode? {
        // Read cached mode from local defaults.
        guard let rawValue = userDefaults.string(forKey: UserDefaultsKeys.cachedDisplayMode) else {
            return nil
        }
        return UsageDisplayMode(rawValue: rawValue)
    }

    /// Persists the given display mode for future sessions
    func saveCachedDisplayMode(_ displayMode: UsageDisplayMode) {
        // Persist to both app and App Group for widget access.
        userDefaults.set(displayMode.rawValue, forKey: UserDefaultsKeys.cachedDisplayMode)
        appGroupDefaults?.set(displayMode.rawValue, forKey: SharedUserDefaultsKeys.cachedDisplayMode)
    }

    /// Converts stored snapshots to the new display mode and refreshes widgets
    func applyDisplayMode(_ displayMode: UsageDisplayMode) {
        let cachedMode = loadCachedDisplayMode() ?? .used
        guard cachedMode != displayMode else {
            // Still persist the cached mode for consistency.
            saveCachedDisplayMode(displayMode)
            return
        }

        for provider in UsageProvider.allCases {
            guard let snapshot = store.loadSnapshot(for: provider) else { continue }
            // Convert stored snapshot between used/remaining modes.
            let convertedSnapshot = snapshot.makeSnapshot(from: cachedMode, to: displayMode)
            do {
                try store.saveSnapshot(convertedSnapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
            } catch {
                logSaveError(error, provider: provider)
            }
        }

        // Update cached mode after rewriting snapshots.
        saveCachedDisplayMode(displayMode)
    }

    /// Logs save errors for diagnostics without breaking UI
    private func logSaveError(_ error: Error, provider: UsageProvider) {
        // Log and continue; UI should not fail due to persistence errors.
        Logger.usage.error("UsageDisplayModeStore: Failed to save snapshot for \(provider.rawValue): \(String(describing: error))")
    }
}
