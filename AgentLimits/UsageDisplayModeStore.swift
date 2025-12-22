// MARK: - UsageDisplayModeStore.swift
// Persists display mode preference and rewrites saved snapshots for widgets.
// Ensures widgets and app show consistent percent values across mode changes.

import Foundation
import WidgetKit

/// Manages persisted display mode and rewrites stored snapshots when toggled
final class UsageDisplayModeStore {
    private let store: UsageSnapshotStore
    private let userDefaults: UserDefaults

    init(
        store: UsageSnapshotStore = UsageSnapshotStore.shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.store = store
        self.userDefaults = userDefaults
    }

    /// Loads the last persisted display mode (if any)
    func loadCachedDisplayMode() -> UsageDisplayMode? {
        guard let rawValue = userDefaults.string(forKey: UserDefaultsKeys.cachedDisplayMode) else {
            return nil
        }
        return UsageDisplayMode(rawValue: rawValue)
    }

    /// Persists the given display mode for future sessions
    func saveCachedDisplayMode(_ displayMode: UsageDisplayMode) {
        userDefaults.set(displayMode.rawValue, forKey: UserDefaultsKeys.cachedDisplayMode)
    }

    /// Converts stored snapshots to the new display mode and refreshes widgets
    func applyDisplayMode(_ displayMode: UsageDisplayMode) {
        let cachedMode = loadCachedDisplayMode() ?? .used
        guard cachedMode != displayMode else {
            saveCachedDisplayMode(displayMode)
            return
        }

        for provider in UsageProvider.allCases {
            guard let snapshot = store.loadSnapshot(for: provider) else { continue }
            let convertedSnapshot = snapshot.makeSnapshot(from: cachedMode, to: displayMode)
            do {
                try store.saveSnapshot(convertedSnapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
            } catch {
                logSaveError(error, provider: provider)
            }
        }

        saveCachedDisplayMode(displayMode)
    }

    /// Logs save errors for diagnostics without breaking UI
    private func logSaveError(_ error: Error, provider: UsageProvider) {
        NSLog(
            "UsageDisplayModeStore: Failed to save snapshot for %@: %@",
            provider.rawValue,
            String(describing: error)
        )
    }
}
