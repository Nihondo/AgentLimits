// MARK: - UsageDisplayModeStore.swift
// Persists display mode preference and updates snapshot display-mode markers.
// Ensures widgets and app show consistent percent values across mode changes.

import Foundation
import OSLog
import WidgetKit

/// Manages persisted display mode and updates stored snapshot markers when toggled
final class UsageDisplayModeStore {
    private let store: UsageSnapshotStore
    private let userDefaults: UserDefaults
    private let appGroupDefaults: UserDefaults?

    init(
        store: UsageSnapshotStore = UsageSnapshotStore.shared,
        userDefaults: UserDefaults = .standard,
        appGroupDefaults: UserDefaults? = AppGroupDefaults.shared
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

    /// Updates stored snapshots with the new display mode and refreshes widgets
    func applyDisplayMode(_ displayMode: UsageDisplayMode) {
        let cachedMode = loadCachedDisplayMode() ?? .used
        let rawMode = displayMode.makeDisplayModeRaw()

        for provider in UsageProvider.allCases {
            guard let snapshot = store.loadSnapshot(for: provider) else { continue }
            if cachedMode == displayMode, snapshot.displayMode == rawMode { continue }
            // Update snapshot display mode without modifying used percent.
            let convertedSnapshot = snapshot.makeSnapshot(for: displayMode)
            do {
                try store.saveSnapshot(convertedSnapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
            } catch {
                logSaveError(error, provider: provider)
            }
        }

        // Update cached mode after updating snapshots.
        saveCachedDisplayMode(displayMode)
    }

    /// Logs save errors for diagnostics without breaking UI
    private func logSaveError(_ error: Error, provider: UsageProvider) {
        // Log and continue; UI should not fail due to persistence errors.
        Logger.usage.error("UsageDisplayModeStore: Failed to save snapshot for \(provider.rawValue): \(String(describing: error))")
    }
}
