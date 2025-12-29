// MARK: - UsageViewModel.swift
// Central state management for usage data fetching and auto-refresh.
// Coordinates WebView login detection, API fetching, and widget updates.

import Foundation
import Combine
import WebKit
import WidgetKit

// MARK: - Usage View Model

/// Main view model managing usage data state, auto-refresh, and provider switching.
/// Coordinates between WebViews, fetchers, and the snapshot store.
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

    /// Internal state for each provider (cached separately for switching)
    private struct ProviderState {
        var snapshot: UsageSnapshot?
        var statusMessage: String
        var isFetching: Bool
        var isAutoRefreshEnabled: Bool?
    }

    private let store: UsageSnapshotStore
    private let codexFetcher: CodexUsageFetcher
    private let claudeFetcher: ClaudeUsageFetcher
    private let webViewPool: UsageWebViewPool
    private let displayModeStore: UsageDisplayModeStore
    private var autoRefreshTask: Task<Void, Never>?
    private var displayMode: UsageDisplayMode = .used
    private var providerStates: [UsageProvider: ProviderState] = [:]
    private var manualRefreshRequests: Set<UsageProvider> = []
    private var lastLoginRedirectAt: [UsageProvider: Date] = [:]

    init(
        webViewPool: UsageWebViewPool,
        store: UsageSnapshotStore? = nil,
        codexFetcher: CodexUsageFetcher? = nil,
        claudeFetcher: ClaudeUsageFetcher? = nil,
        displayModeStore: UsageDisplayModeStore? = nil,
        selectedProvider: UsageProvider = .chatgptCodex
    ) {
        let useStore = store ?? UsageSnapshotStore.shared
        let useDisplayModeStore = displayModeStore ?? UsageDisplayModeStore()
        let useCodexFetcher = codexFetcher ?? CodexUsageFetcher()
        let useClaudeFetcher = claudeFetcher ?? ClaudeUsageFetcher()
        let cachedMode = useDisplayModeStore.loadCachedDisplayMode() ?? .used

        var useProviderStates: [UsageProvider: ProviderState] = [:]
        for provider in UsageProvider.allCases {
            if let cachedSnapshot = useStore.loadSnapshot(for: provider) {
                useProviderStates[provider] = Self.makeProviderState(
                    snapshot: cachedSnapshot.makeSnapshot(from: cachedMode, to: .used)
                )
            } else {
                useProviderStates[provider] = Self.makeProviderState(snapshot: nil)
            }
        }

        let useSelectedState = useProviderStates[selectedProvider] ?? Self.makeProviderState(snapshot: nil)

        self.webViewPool = webViewPool
        self.store = useStore
        self.codexFetcher = useCodexFetcher
        self.claudeFetcher = useClaudeFetcher
        self.displayModeStore = useDisplayModeStore
        self.selectedProvider = selectedProvider
        self.providerStates = useProviderStates
        self.snapshot = useSelectedState.snapshot
        self.statusMessage = useSelectedState.statusMessage
        self.isFetching = useSelectedState.isFetching
    }

    // MARK: - Auto Refresh

    /// Starts the auto-refresh timer for eligible providers
    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task {
            await refreshAutoEligibleProviders()
            while !Task.isCancelled {
                try? await Task.sleep(for: UsageRefreshConfig.refreshIntervalDuration)
                await refreshAutoEligibleProviders()
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

    /// Triggers an immediate refresh for the current provider
    func fetchNow() {
        let provider = selectedProvider
        manualRefreshRequests.insert(provider)
        let store = webViewPool.getWebViewStore(for: provider)
        if isUsageURL(store.webView.url, provider: provider) && store.isPageReady {
            _ = consumeManualRefreshRequest(for: provider)
            Task {
                await handleLoginAndFetch(for: provider)
            }
        } else {
            store.reloadFromOrigin()
        }
    }

    // MARK: - Provider State Management

    /// Updates published properties when provider selection changes
    func updateSelectedProviderState() {
        let provider = selectedProvider
        let state = getProviderState(for: provider)
        Task { @MainActor in
            guard provider == self.selectedProvider else { return }
            snapshot = state.snapshot
            statusMessage = state.statusMessage
            isFetching = state.isFetching
        }
    }

    /// Updates display mode and persists to all snapshots
    func updateDisplayMode(_ displayMode: UsageDisplayMode) {
        self.displayMode = displayMode
        displayModeStore.applyDisplayMode(displayMode)
        updateSelectedProviderState()
    }

    // MARK: - Page Ready Handling

    /// Called when WebView page finishes loading; triggers fetch if logged in
    func handlePageReadyChange(for provider: UsageProvider, isReady: Bool) {
        guard isReady else { return }
        let isManualRefresh = consumeManualRefreshRequest(for: provider)
        if !isManualRefresh {
            guard providerStates[provider]?.isAutoRefreshEnabled != true else { return }
        }
        guard providerStates[provider]?.isFetching != true else { return }
        Task {
            await handleLoginAndFetch(for: provider)
        }
    }

    /// Called when cookies change; triggers login-based navigation for Claude
    func handleCookieChange(for provider: UsageProvider) {
        guard provider == .claudeCode else { return }
        let store = webViewPool.getWebViewStore(for: provider)
        Task {
            let isLoggedIn = await checkLoginStatus(for: provider, using: store.webView)
            guard isLoggedIn else { return }
            guard !isUsageURL(store.webView.url, provider: provider) else { return }
            guard canRedirectLogin(for: provider) else { return }
            store.reloadFromOrigin()
        }
    }

    private func refreshAutoEligibleProviders() async {
        for provider in UsageProvider.allCases {
            let isEnabled = providerStates[provider]?.isAutoRefreshEnabled
            let shouldRefresh = isEnabled == true || (isEnabled == nil && provider == selectedProvider)
            guard shouldRefresh else { continue }
            await refreshSnapshot(for: provider)
        }
    }

    private func refreshSnapshot(for provider: UsageProvider) async {
        if providerStates[provider]?.isFetching == true {
            return
        }
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        guard webViewStore.isPageReady else {
            updateStatusMessage("status.loadingLogin".localized(), for: provider)
            return
        }

        setFetching(true, for: provider)
        defer { setFetching(false, for: provider) }

        do {
            let snapshot = try await fetchSnapshot(for: provider, using: webViewStore.webView)
            let snapshotToSave = snapshot.makeSnapshot(from: .used, to: displayMode)
            try store.saveSnapshot(snapshotToSave)
            displayModeStore.saveCachedDisplayMode(displayMode)
            var state = getProviderState(for: provider)
            state.snapshot = snapshot
            state.isAutoRefreshEnabled = true
            providerStates[provider] = state
            updateStatusMessage("status.updated".localized(), for: provider)
            if provider == selectedProvider {
                self.snapshot = snapshot
            }
            WidgetCenter.shared.reloadTimelines(ofKind: snapshot.provider.widgetKind)

            // Check thresholds and send notifications if needed
            await ThresholdNotificationManager.shared.checkThresholdsIfNeeded(for: snapshot)
        } catch {
            if shouldDisableAutoRefresh(for: provider, error: error) {
                var state = getProviderState(for: provider)
                state.isAutoRefreshEnabled = false
                providerStates[provider] = state
            }
            updateStatusMessage(error.localizedDescription, for: provider)
        }
    }

    private func handleLoginAndFetch(for provider: UsageProvider) async {
        let store = webViewPool.getWebViewStore(for: provider)
        let isLoggedIn = await checkLoginStatus(for: provider, using: store.webView)
        guard isLoggedIn else {
            updateStatusMessage("status.loadingLogin".localized(), for: provider)
            return
        }

        if !isUsageURL(store.webView.url, provider: provider) {
            store.reloadFromOrigin()
            return
        }

        await refreshSnapshot(for: provider)
    }

    private func checkLoginStatus(for provider: UsageProvider, using webView: WKWebView) async -> Bool {
        switch provider {
        case .chatgptCodex:
            return await codexFetcher.hasValidSession(using: webView)
        case .claudeCode:
            return await claudeFetcher.hasValidSession(using: webView)
        }
    }

    private func isUsageURL(_ url: URL?, provider: UsageProvider) -> Bool {
        guard let url else { return false }
        let usageURL = provider.usageURL
        return url.scheme == usageURL.scheme
            && url.host == usageURL.host
            && url.path == usageURL.path
    }

    private func consumeManualRefreshRequest(for provider: UsageProvider) -> Bool {
        manualRefreshRequests.remove(provider) != nil
    }

    private func fetchSnapshot(for provider: UsageProvider, using webView: WKWebView) async throws -> UsageSnapshot {
        switch provider {
        case .chatgptCodex:
            return try await codexFetcher.fetchUsageSnapshot(using: webView)
        case .claudeCode:
            return try await claudeFetcher.fetchUsageSnapshot(using: webView)
        }
    }

    private func setFetching(_ isFetching: Bool, for provider: UsageProvider) {
        var state = getProviderState(for: provider)
        state.isFetching = isFetching
        providerStates[provider] = state
        if provider == selectedProvider {
            self.isFetching = isFetching
        }
    }

    private func updateStatusMessage(_ message: String, for provider: UsageProvider) {
        var state = getProviderState(for: provider)
        state.statusMessage = message
        providerStates[provider] = state
        if provider == selectedProvider {
            statusMessage = message
        }
    }

    private static func makeProviderState(snapshot: UsageSnapshot?) -> ProviderState {
        ProviderState(
            snapshot: snapshot,
            statusMessage: "status.notFetched".localized(),
            isFetching: false,
            isAutoRefreshEnabled: nil
        )
    }

    private func getProviderState(for provider: UsageProvider) -> ProviderState {
        providerStates[provider] ?? Self.makeProviderState(snapshot: nil)
    }

    private func shouldDisableAutoRefresh(for provider: UsageProvider, error: Error) -> Bool {
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
        let normalized = message.lowercased()
        return normalized.contains("missing access token")
            || normalized.contains("missing organization")
            || normalized.contains("unauthorized")
            || normalized.contains("http 401")
            || normalized.contains("http 403")
    }

    private func canRedirectLogin(for provider: UsageProvider) -> Bool {
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
