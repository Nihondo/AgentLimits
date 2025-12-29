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
    private var autoRefreshTask: Task<Void, Never>?

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
                statusMessages[provider] = formatLastUpdated(cached.fetchedAt)
            }
        }
    }

    // MARK: - Settings Management

    /// Updates settings for a provider
    func updateSettings(_ newSettings: CCUsageSettings) {
        settings[newSettings.provider] = newSettings
        settingsStore.updateSettings(newSettings)
    }

    // MARK: - Auto Refresh

    /// Starts the auto-refresh timer
    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task {
            // Fetch immediately on start
            await refreshEnabledProviders()
            while !Task.isCancelled {
                try? await Task.sleep(for: TokenUsageRefreshConfig.refreshIntervalDuration)
                guard isAutoRefreshEnabled else { continue }
                await refreshEnabledProviders()
            }
        }
    }

    /// Stops the auto-refresh timer
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
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
                    await self.refresh(for: provider)
                }
            }
        }
    }

    /// Refreshes data for all providers (regardless of enabled state)
    func refreshAllProviders() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in TokenUsageProvider.allCases {
                group.addTask {
                    await self.refresh(for: provider)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func refresh(for provider: TokenUsageProvider) async {
        guard isFetching[provider] != true else { return }
        isFetching[provider] = true
        defer { isFetching[provider] = false }

        do {
            let snapshot = try await fetcher.fetchSnapshot(for: provider)
            try snapshotStore.saveSnapshot(snapshot)
            snapshots[provider] = snapshot
            statusMessages[provider] = formatLastUpdated(snapshot.fetchedAt)
            WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
        } catch {
            statusMessages[provider] = error.localizedDescription
        }
    }

    private func formatLastUpdated(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "tokenUsage.updated".localized() + formatter.string(from: date)
    }
}
