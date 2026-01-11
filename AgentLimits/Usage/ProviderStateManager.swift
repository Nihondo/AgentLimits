// MARK: - ProviderStateManager.swift
// Manages per-provider state for usage data fetching.
// Separates state management concerns from UsageViewModel.

import Foundation

// MARK: - Provider State

/// Last fetch outcome for usage data.
enum ProviderFetchStatus {
    case notFetched
    case success(Date)
    case failure(String)
}

/// Internal state for each provider
struct ProviderState {
    var snapshot: UsageSnapshot?
    var statusMessage: String
    var isFetching: Bool
    var isAutoRefreshEnabled: Bool?
    var lastFetchStatus: ProviderFetchStatus

    /// Creates a default state with optional snapshot
    static func initial(snapshot: UsageSnapshot? = nil) -> ProviderState {
        let fetchStatus: ProviderFetchStatus
        if let snapshot {
            fetchStatus = .success(snapshot.fetchedAt)
        } else {
            fetchStatus = .notFetched
        }
        return ProviderState(
            snapshot: snapshot,
            statusMessage: snapshot == nil ? "status.notFetched".localized() : "status.updated".localized(),
            isFetching: false,
            isAutoRefreshEnabled: nil,
            lastFetchStatus: fetchStatus
        )
    }
}

// MARK: - Provider State Manager

/// Manages per-provider state for usage tracking.
/// Centralizes state storage and updates for all providers.
@MainActor
final class ProviderStateManager {
    /// Current state for each provider
    private var states: [UsageProvider: ProviderState] = [:]

    /// Callback for state changes (used by ViewModel for objectWillChange)
    var onStateChange: (() -> Void)?

    // MARK: - Initialization

    init() {
        for provider in UsageProvider.allCases {
            states[provider] = .initial()
        }
    }

    /// Initializes with cached snapshots from store
    func loadCachedSnapshots(from store: UsageSnapshotStore) {
        for provider in UsageProvider.allCases {
            if let cachedSnapshot = store.loadSnapshot(for: provider) {
                // Keep stored used% intact and use snapshot display mode as-is.
                states[provider] = .initial(snapshot: cachedSnapshot)
            }
        }
    }

    // MARK: - State Access

    /// Returns state for a provider
    func getState(for provider: UsageProvider) -> ProviderState {
        states[provider] ?? .initial()
    }

    /// Returns all provider snapshots (for menu bar status display)
    var allSnapshots: [UsageProvider: UsageSnapshot] {
        var result: [UsageProvider: UsageSnapshot] = [:]
        for (provider, state) in states {
            if let snapshot = state.snapshot {
                result[provider] = snapshot
            }
        }
        return result
    }

    /// Returns fetch status for all providers
    var allFetchStatuses: [UsageProvider: ProviderFetchStatus] {
        var result: [UsageProvider: ProviderFetchStatus] = [:]
        for (provider, state) in states {
            result[provider] = state.lastFetchStatus
        }
        return result
    }

    // MARK: - State Updates

    /// Updates the entire state for a provider
    func setState(_ state: ProviderState, for provider: UsageProvider) {
        // Replace entire state and notify observers.
        states[provider] = state
        onStateChange?()
    }

    /// Updates only the snapshot for a provider
    func setSnapshot(_ snapshot: UsageSnapshot?, for provider: UsageProvider) {
        // Update snapshot without touching other state fields.
        var state = getState(for: provider)
        state.snapshot = snapshot
        states[provider] = state
        onStateChange?()
    }

    /// Updates fetching status for a provider
    func setFetching(_ isFetching: Bool, for provider: UsageProvider) {
        // Update fetch flag for provider.
        var state = getState(for: provider)
        state.isFetching = isFetching
        states[provider] = state
    }

    /// Updates status message for a provider
    func setStatusMessage(_ message: String, for provider: UsageProvider) {
        // Update status message for provider.
        var state = getState(for: provider)
        state.statusMessage = message
        states[provider] = state
    }

    /// Updates last fetch status for a provider
    func setFetchStatus(_ status: ProviderFetchStatus, for provider: UsageProvider) {
        // Update last fetch status for provider.
        var state = getState(for: provider)
        state.lastFetchStatus = status
        states[provider] = state
        onStateChange?()
    }

    /// Updates auto-refresh enabled status for a provider
    func setAutoRefreshEnabled(_ enabled: Bool?, for provider: UsageProvider) {
        // Update auto-refresh flag for provider.
        var state = getState(for: provider)
        state.isAutoRefreshEnabled = enabled
        states[provider] = state
    }

    /// Updates snapshot and marks auto-refresh as enabled
    func updateAfterSuccessfulFetch(
        snapshot: UsageSnapshot,
        for provider: UsageProvider
    ) {
        // Store snapshot and mark auto-refresh as enabled.
        var state = getState(for: provider)
        state.snapshot = snapshot
        state.lastFetchStatus = .success(snapshot.fetchedAt)
        state.isAutoRefreshEnabled = true
        states[provider] = state
        onStateChange?()
    }

    // MARK: - Auto Refresh Eligibility

    /// Returns providers eligible for auto-refresh
    func autoRefreshEligibleProviders(selectedProvider: UsageProvider) -> [UsageProvider] {
        // Eligible when explicitly enabled, or undetermined but selected.
        UsageProvider.allCases.filter { provider in
            let isEnabled = states[provider]?.isAutoRefreshEnabled
            // Refresh if explicitly enabled, or if nil (undetermined) and is selected
            return isEnabled == true || (isEnabled == nil && provider == selectedProvider)
        }
    }
}
