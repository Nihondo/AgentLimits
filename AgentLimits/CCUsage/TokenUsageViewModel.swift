// MARK: - TokenUsageViewModel.swift
// State management for ccusage token usage data with auto-refresh support.

import Foundation
import Combine
import WidgetKit

/// ViewModel for managing ccusage token usage data
@MainActor
final class TokenUsageViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Token usage snapshots per provider
    @Published private(set) var snapshots: [TokenUsageProvider: TokenUsageSnapshot] = [:]
    /// Status messages per provider
    @Published private(set) var statusMessages: [TokenUsageProvider: String] = [:]
    /// Fetching state per provider
    @Published private(set) var isFetching: [TokenUsageProvider: Bool] = [:]
    /// Settings per provider
    @Published var settings: [TokenUsageProvider: CCUsageSettings] = [:]
    /// Whether auto-refresh is enabled
    @Published var isAutoRefreshEnabled: Bool = true

    // MARK: - Private Properties

    private let fetcher: CCUsageFetcher
    private let snapshotStore: TokenUsageSnapshotStore
    private let settingsStore: CCUsageSettingsStore
    private var autoRefreshCoordinator: AutoRefreshCoordinator?

    // MARK: - Initialization

    init(
        fetcher: CCUsageFetcher? = nil,
        snapshotStore: TokenUsageSnapshotStore? = nil,
        settingsStore: CCUsageSettingsStore? = nil
    ) {
        let resolvedFetcher = fetcher ?? CCUsageFetcher()
        let resolvedSnapshotStore = snapshotStore ?? .shared
        let resolvedSettingsStore = settingsStore ?? .shared

        self.fetcher = resolvedFetcher
        self.snapshotStore = resolvedSnapshotStore
        self.settingsStore = resolvedSettingsStore

        // Load settings
        settings = resolvedSettingsStore.loadSettings()

        // Initialize state for all providers
        for provider in TokenUsageProvider.allCases {
            isFetching[provider] = false
            statusMessages[provider] = "tokenUsage.notFetched".localized()

            // Load cached snapshot
            if let cached = resolvedSnapshotStore.loadSnapshot(for: provider) {
                snapshots[provider] = cached
                // Show last updated time for cached snapshot.
                statusMessages[provider] = formatLastUpdated(cached.fetchedAt)
            }
        }
    }

    // MARK: - Settings Management

    /// Updates settings for a provider
    func updateSettings(_ newSettings: CCUsageSettings) {
        // Persist updated settings for the selected provider.
        settings[newSettings.provider] = newSettings
        settingsStore.updateSettings(newSettings)
    }

    // MARK: - Auto Refresh

    /// Starts the auto-refresh timer.
    /// Uses AutoRefreshCoordinator to manage timer lifecycle.
    func startAutoRefresh() {
        guard autoRefreshCoordinator == nil else { return }
        autoRefreshCoordinator = AutoRefreshCoordinator(
            intervalProvider: { TokenUsageRefreshConfig.refreshIntervalDuration },
            refreshHandler: { [weak self] in
                // Skip refresh when disabled in UI.
                guard let self, self.isAutoRefreshEnabled else { return }
                await self.refreshEnabledProviders()
            }
        )
        autoRefreshCoordinator?.start()
    }

    /// Stops the auto-refresh timer
    func stopAutoRefresh() {
        autoRefreshCoordinator?.stop()
        autoRefreshCoordinator = nil
    }

    /// Restarts the auto-refresh timer (useful when interval changes)
    func restartAutoRefresh() {
        stopAutoRefresh()
        startAutoRefresh()
    }

    // MARK: - Manual Refresh

    /// Refreshes data for a single provider
    func refreshNow(for provider: TokenUsageProvider) async {
        await refresh(for: provider)
    }

    /// Refreshes data for all enabled providers
    func refreshEnabledProviders() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in TokenUsageProvider.allCases {
                guard settings[provider]?.isEnabled == true else { continue }
                group.addTask {
                    // Refresh each enabled provider in parallel.
                    await self.refresh(for: provider)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func refresh(for provider: TokenUsageProvider) async {
        // Prevent overlapping fetches per provider.
        guard isFetching[provider] != true else { return }
        isFetching[provider] = true
        defer { isFetching[provider] = false }

        do {
            // Fetch snapshot via CLI and persist to App Group store.
            let snapshot = try await fetcher.fetchSnapshot(for: provider)
            try snapshotStore.saveSnapshot(snapshot)
            snapshots[provider] = snapshot
            statusMessages[provider] = formatLastUpdated(snapshot.fetchedAt)
            // Notify widgets to update with latest data.
            WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
        } catch {
            // Report error to UI.
            statusMessages[provider] = error.localizedDescription
        }
    }

    /// Formats the last updated time for display.
    /// Uses a cached DateFormatter to avoid repeated allocations.
    /// - Parameter date: The date to format
    /// - Returns: Localized string like "Updated: 10:30 AM"
    private func formatLastUpdated(_ date: Date) -> String {
        // Format timestamp for display with localized prefix.
        return "tokenUsage.updated".localized() + Self.timeFormatter.string(from: date)
    }

    // MARK: - Static Date Formatters

    /// Cached time formatter for displaying last updated time (short time style only)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
