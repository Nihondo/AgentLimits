// MARK: - UsageViewModel.swift
// Central state management for usage data fetching and auto-refresh.
// Coordinates WebView login detection, API fetching, and widget updates.

import Combine
import Foundation
import WebKit
import WidgetKit

// MARK: - Usage View Model

/// Main view model managing usage data state, auto-refresh, and provider switching.
/// Coordinates between WebViews, fetchers, and the snapshot store.
/// Uses ProviderStateManager for per-provider state management.
@MainActor
final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var statusMessage: String
    @Published var isFetching: Bool
    @Published var selectedProvider: UsageProvider {
        didSet {
            updateSelectedProviderState()
        }
    }

    private let store: UsageSnapshotStore
    private let codexFetcher: CodexUsageFetcher
    private let claudeFetcher: ClaudeUsageFetcher
    private let webViewPool: UsageWebViewPool
    private let displayModeStore: UsageDisplayModeStore
    private let stateManager: ProviderStateManager
    private var autoRefreshCoordinator: AutoRefreshCoordinator?
    private var displayMode: UsageDisplayMode = .used
    private var manualRefreshRequests: Set<UsageProvider> = []
    private var lastLoginRedirectAt: [UsageProvider: Date] = [:]

    init(
        webViewPool: UsageWebViewPool,
        store: UsageSnapshotStore? = nil,
        codexFetcher: CodexUsageFetcher? = nil,
        claudeFetcher: ClaudeUsageFetcher? = nil,
        displayModeStore: UsageDisplayModeStore? = nil,
        stateManager: ProviderStateManager? = nil,
        selectedProvider: UsageProvider = .chatgptCodex
    ) {
        let useStore = store ?? UsageSnapshotStore.shared
        let useDisplayModeStore = displayModeStore ?? UsageDisplayModeStore()
        let useCodexFetcher = codexFetcher ?? CodexUsageFetcher()
        let useClaudeFetcher = claudeFetcher ?? ClaudeUsageFetcher()
        let useStateManager = stateManager ?? ProviderStateManager()
        // Load cached snapshots into state manager
        useStateManager.loadCachedSnapshots(from: useStore)

        let selectedState = useStateManager.getState(for: selectedProvider)

        self.webViewPool = webViewPool
        self.store = useStore
        self.codexFetcher = useCodexFetcher
        self.claudeFetcher = useClaudeFetcher
        self.displayModeStore = useDisplayModeStore
        self.stateManager = useStateManager
        self.selectedProvider = selectedProvider
        self.snapshot = selectedState.snapshot
        self.statusMessage = selectedState.statusMessage
        self.isFetching = selectedState.isFetching

        // Set up state change callback for menu bar updates
        useStateManager.onStateChange = { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Public Accessors

    /// Returns all provider snapshots for menu bar status display
    var snapshots: [UsageProvider: UsageSnapshot] {
        stateManager.allSnapshots
    }

    /// Returns latest fetch statuses for all providers (for summary UI)
    var fetchStatuses: [UsageProvider: ProviderFetchStatus] {
        stateManager.allFetchStatuses
    }

    /// Checks if user is logged in for the specified provider.
    /// Used by popup auto-close to detect OAuth completion.
    func checkLoginStatus(for provider: UsageProvider) async -> Bool {
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        return await checkLoginStatus(for: provider, using: webViewStore.webView)
    }

    // MARK: - Auto Refresh

    /// Starts the auto-refresh timer for eligible providers.
    /// Uses AutoRefreshCoordinator to manage timer lifecycle.
    func startAutoRefresh() {
        guard autoRefreshCoordinator == nil else { return }
        autoRefreshCoordinator = AutoRefreshCoordinator(
            intervalProvider: { UsageRefreshConfig.refreshIntervalDuration },
            refreshHandler: { [weak self] in
                await self?.refreshAutoEligibleProviders()
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

    /// Triggers an immediate refresh for the specified provider (for widget tap)
    func refreshNow(for provider: UsageProvider) async {
        await refreshSnapshot(for: provider)
    }

    /// Triggers an immediate refresh for the current provider
    func fetchNow() {
        let provider = selectedProvider
        // Record manual refresh intent to allow fetch on page-ready callback.
        manualRefreshRequests.insert(provider)
        let store = webViewPool.getWebViewStore(for: provider)
        if isUsageURL(store.webView.url, provider: provider) && store.isPageReady {
            // If already on the usage page, proceed directly to fetch.
            _ = consumeManualRefreshRequest(for: provider)
            Task {
                await handleLoginAndFetch(for: provider)
            }
        } else {
            // Otherwise reload to reach the usage page (login flow).
            store.reloadFromOrigin()
        }
    }

    // MARK: - Provider State Management

    /// Updates published properties when provider selection changes
    func updateSelectedProviderState() {
        let provider = selectedProvider
        let state = stateManager.getState(for: provider)
        Task { @MainActor in
            // Prevent stale updates when selection changed mid-task.
            guard provider == self.selectedProvider else { return }
            snapshot = state.snapshot
            statusMessage = state.statusMessage
            isFetching = state.isFetching
        }
    }

    /// Updates display mode and persists to all snapshots
    func updateDisplayMode(_ displayMode: UsageDisplayMode) {
        // Apply new mode, persist it, and refresh UI state.
        self.displayMode = displayMode
        displayModeStore.applyDisplayMode(displayMode)
        updateSelectedProviderState()
    }

    // MARK: - Page Ready Handling

    /// Called when WebView page finishes loading; triggers fetch if logged in
    func handlePageReadyChange(for provider: UsageProvider, isReady: Bool) {
        guard isReady else { return }
        // Manual refresh has priority; otherwise honor auto-refresh eligibility.
        let isManualRefresh = consumeManualRefreshRequest(for: provider)
        let state = stateManager.getState(for: provider)
        if !isManualRefresh {
            guard state.isAutoRefreshEnabled != true else { return }
        }
        guard !state.isFetching else { return }
        Task {
            await handleLoginAndFetch(for: provider)
        }
    }

    /// Called when cookies change; triggers login-based navigation for Claude
    func handleCookieChange(for provider: UsageProvider) {
        guard provider == .claudeCode else { return }
        let store = webViewPool.getWebViewStore(for: provider)
        Task {
            // Only redirect when a valid session is detected and cooldown allows it.
            let isLoggedIn = await checkLoginStatus(for: provider, using: store.webView)
            guard isLoggedIn else { return }
            guard !isUsageURL(store.webView.url, provider: provider) else { return }
            guard canRedirectLogin(for: provider) else { return }
            store.reloadFromOrigin()
        }
    }

    private func refreshAutoEligibleProviders() async {
        // Refresh providers that are enabled or selected.
        let eligibleProviders = stateManager.autoRefreshEligibleProviders(selectedProvider: selectedProvider)
        for provider in eligibleProviders {
            await refreshSnapshot(for: provider)
        }
    }

    private func refreshSnapshot(for provider: UsageProvider) async {
        let currentState = stateManager.getState(for: provider)
        guard !currentState.isFetching else { return }

        let webViewStore = webViewPool.getWebViewStore(for: provider)
        guard webViewStore.isPageReady else {
            // Update status while waiting for login page to load.
            stateManager.setStatusMessage("status.loadingLogin".localized(), for: provider)
            return
        }

        // Track fetching state for both per-provider and selected provider UI.
        stateManager.setFetching(true, for: provider)
        if provider == selectedProvider {
            isFetching = true
        }
        defer {
            stateManager.setFetching(false, for: provider)
            if provider == selectedProvider {
                isFetching = false
            }
        }

        do {
            // Fetch latest snapshot from provider and persist with display-mode marker.
            let fetchedSnapshot = try await fetchSnapshot(for: provider, using: webViewStore.webView)
            let snapshotToSave = fetchedSnapshot.makeSnapshot(for: displayMode)
            try store.saveSnapshot(snapshotToSave)
            displayModeStore.saveCachedDisplayMode(displayMode)
            stateManager.updateAfterSuccessfulFetch(snapshot: snapshotToSave, for: provider)
            stateManager.setStatusMessage("status.updated".localized(), for: provider)
            if provider == selectedProvider {
                self.snapshot = snapshotToSave
                statusMessage = "status.updated".localized()
            }
            // Notify widgets to refresh their timelines.
            WidgetCenter.shared.reloadTimelines(ofKind: snapshotToSave.provider.widgetKind)

            // Check thresholds and send notifications if needed
            await ThresholdNotificationManager.shared.checkThresholdsIfNeeded(for: fetchedSnapshot)
        } catch {
            // Disable auto-refresh on auth-related errors to prevent repeated failures.
            if shouldDisableAutoRefresh(for: provider, error: error) {
                stateManager.setAutoRefreshEnabled(false, for: provider)
            }
            stateManager.setFetchStatus(.failure(error.localizedDescription), for: provider)
            stateManager.setStatusMessage(error.localizedDescription, for: provider)
            if provider == selectedProvider {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func handleLoginAndFetch(for provider: UsageProvider) async {
        let store = webViewPool.getWebViewStore(for: provider)
        // Verify login status before attempting API fetch.
        let isLoggedIn = await checkLoginStatus(for: provider, using: store.webView)
        guard isLoggedIn else {
            stateManager.setStatusMessage("status.loadingLogin".localized(), for: provider)
            if provider == selectedProvider {
                statusMessage = "status.loadingLogin".localized()
            }
            return
        }

        if !isUsageURL(store.webView.url, provider: provider) {
            // Navigate to the usage page when logged in but not on target URL.
            store.reloadFromOrigin()
            return
        }

        await refreshSnapshot(for: provider)
    }

    private func checkLoginStatus(for provider: UsageProvider, using webView: WKWebView) async -> Bool {
        // Delegate to provider-specific fetchers.
        switch provider {
        case .chatgptCodex:
            return await codexFetcher.hasValidSession(using: webView)
        case .claudeCode:
            return await claudeFetcher.hasValidSession(using: webView)
        }
    }

    private func isUsageURL(_ url: URL?, provider: UsageProvider) -> Bool {
        // Compare scheme/host/path to avoid false positives.
        guard let url else { return false }
        let usageURL = provider.usageURL
        return url.scheme == usageURL.scheme
            && url.host == usageURL.host
            && url.path == usageURL.path
    }

    private func consumeManualRefreshRequest(for provider: UsageProvider) -> Bool {
        // Consume and clear manual refresh flag for the provider.
        manualRefreshRequests.remove(provider) != nil
    }

    private func fetchSnapshot(for provider: UsageProvider, using webView: WKWebView) async throws -> UsageSnapshot {
        // Delegate fetch to provider-specific fetchers.
        switch provider {
        case .chatgptCodex:
            return try await codexFetcher.fetchUsageSnapshot(using: webView)
        case .claudeCode:
            return try await claudeFetcher.fetchUsageSnapshot(using: webView)
        }
    }

    private func shouldDisableAutoRefresh(for provider: UsageProvider, error: Error) -> Bool {
        // Disable auto-refresh only for authentication/organization issues.
        switch provider {
        case .chatgptCodex:
            guard let error = error as? CodexUsageFetcherError else { return false }
            switch error {
            case .scriptFailed(let message):
                return isLoginRequiredMessage(message)
            case .invalidResponse, .pageNotReady:
                return false
            }
        case .claudeCode:
            guard let error = error as? ClaudeUsageFetcherError else { return false }
            switch error {
            case .missingOrganization:
                return true
            case .scriptFailed(let message):
                return isLoginRequiredMessage(message)
            case .invalidResponse:
                return false
            }
        }
    }

    private func isLoginRequiredMessage(_ message: String) -> Bool {
        // Normalize and check for common auth-related error markers.
        let normalized = message.lowercased()
        return normalized.contains("missing access token")
            || normalized.contains("missing organization")
            || normalized.contains("unauthorized")
            || normalized.contains("http 401")
            || normalized.contains("http 403")
    }

    private func canRedirectLogin(for provider: UsageProvider) -> Bool {
        // Throttle redirects to avoid excessive reloads.
        let now = Date()
        let cooldown: TimeInterval = 5
        if let lastRedirectAt = lastLoginRedirectAt[provider],
           now.timeIntervalSince(lastRedirectAt) < cooldown {
            return false
        }
        lastLoginRedirectAt[provider] = now
        return true
    }
}
