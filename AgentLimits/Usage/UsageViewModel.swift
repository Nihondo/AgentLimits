// MARK: - UsageViewModel.swift
// Central state management for usage data fetching and auto-refresh.
//
// Codex and Claude now bypass WKWebView entirely — they read credentials
// from local CLI installs (`~/.codex/auth.json` / `Claude Code-credentials`
// keychain item) and call the provider HTTPS endpoints directly. Copilot
// continues to use the WebView pool because GitHub's billing endpoint is
// only reachable from a logged-in browser session.
//
// 5-minute minimum poll interval enforced for Codex/Claude.

import Combine
import Foundation
import OSLog
import WebKit
import WidgetKit

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
    private let copilotFetcher: CopilotUsageFetcher
    private let copilotBillingFetcher: CopilotBillingFetcher
    private let webViewPool: UsageWebViewPool
    private let displayModeStore: UsageDisplayModeStore
    private let stateManager: ProviderStateManager
    private var autoRefreshCoordinator: AutoRefreshCoordinator?
    private var displayMode: UsageDisplayMode = .used
    private var manualRefreshRequests: Set<UsageProvider> = []
    private var autoRecoveryInFlight: Set<UsageProvider> = []
    private var lastLoginRedirectAt: [UsageProvider: Date] = [:]

    /// Tracks the last successful fetch per provider. Used to enforce the
    /// codex-island minimum 5-minute poll guard for Codex/Claude, which
    /// share daily quotas with the user's actual CLI sessions.
    private var lastSuccessfulFetchAt: [UsageProvider: Date] = [:]

    init(
        webViewPool: UsageWebViewPool,
        store: UsageSnapshotStore? = nil,
        codexFetcher: CodexUsageFetcher? = nil,
        claudeFetcher: ClaudeUsageFetcher? = nil,
        copilotFetcher: CopilotUsageFetcher? = nil,
        displayModeStore: UsageDisplayModeStore? = nil,
        stateManager: ProviderStateManager? = nil,
        selectedProvider: UsageProvider = .chatgptCodex
    ) {
        let useStore = store ?? UsageSnapshotStore.shared
        let useDisplayModeStore = displayModeStore ?? UsageDisplayModeStore()
        let useCodexFetcher = codexFetcher ?? CodexUsageFetcher()
        let useClaudeFetcher = claudeFetcher ?? ClaudeUsageFetcher()
        let useCopilotFetcher = copilotFetcher ?? CopilotUsageFetcher()
        let useStateManager = stateManager ?? ProviderStateManager()
        useStateManager.loadCachedSnapshots(from: useStore)
        let selectedState = useStateManager.getState(for: selectedProvider)

        self.webViewPool = webViewPool
        self.store = useStore
        self.codexFetcher = useCodexFetcher
        self.claudeFetcher = useClaudeFetcher
        self.copilotFetcher = useCopilotFetcher
        self.copilotBillingFetcher = CopilotBillingFetcher()
        self.displayModeStore = useDisplayModeStore
        self.stateManager = useStateManager
        self.selectedProvider = selectedProvider
        self.snapshot = selectedState.snapshot
        self.statusMessage = selectedState.statusMessage
        self.isFetching = selectedState.isFetching

        useStateManager.onStateChange = { [weak self] in
            self?.objectWillChange.send()
        }

        // Seed lastSuccessfulFetchAt from cached snapshots so the 5-min guard
        // survives an app restart.
        for (provider, snapshot) in useStateManager.allSnapshots {
            lastSuccessfulFetchAt[provider] = snapshot.fetchedAt
        }
    }

    // MARK: - Public Accessors

    var snapshots: [UsageProvider: UsageSnapshot] {
        stateManager.allSnapshots
    }

    var fetchStatuses: [UsageProvider: ProviderFetchStatus] {
        stateManager.allFetchStatuses
    }

    /// Checks login state for `provider`. Native fetchers answer from
    /// disk/keychain; Copilot still asks the WebView.
    func checkLoginStatus(for provider: UsageProvider) async -> Bool {
        switch provider {
        case .chatgptCodex:
            return codexFetcher.hasValidSession()
        case .claudeCode:
            return claudeFetcher.hasValidSession()
        case .githubCopilot:
            let webViewStore = webViewPool.getWebViewStore(for: provider)
            return await checkLoginStatusViaWebView(for: provider, using: webViewStore.webView)
        }
    }

    // MARK: - Auto Refresh

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

    func stopAutoRefresh() {
        autoRefreshCoordinator?.stop()
        autoRefreshCoordinator = nil
    }

    func restartAutoRefresh() {
        stopAutoRefresh()
        startAutoRefresh()
    }

    // MARK: - Manual Refresh

    func refreshNow(for provider: UsageProvider) async {
        await refreshSnapshot(for: provider, isManual: true)
    }

    func fetchNow() {
        let provider = selectedProvider
        switch provider {
        case .chatgptCodex, .claudeCode:
            Task { await refreshSnapshot(for: provider, isManual: true) }
        case .githubCopilot:
            manualRefreshRequests.insert(provider)
            let webViewStore = webViewPool.getWebViewStore(for: provider)
            if isUsageURL(webViewStore.webView.url, provider: provider) && webViewStore.isPageReady {
                _ = consumeManualRefreshRequest(for: provider)
                Task {
                    await handleCopilotLoginAndFetch(for: provider)
                }
            } else {
                webViewStore.reloadFromOrigin()
            }
        }
    }

    // MARK: - Provider State Management

    func updateSelectedProviderState() {
        let provider = selectedProvider
        let state = stateManager.getState(for: provider)
        Task { @MainActor in
            guard provider == self.selectedProvider else { return }
            snapshot = state.snapshot
            statusMessage = state.statusMessage
            isFetching = state.isFetching
        }
    }

    func updateDisplayMode(_ displayMode: UsageDisplayMode) {
        let displayMode = displayMode.normalizedSelectableMode
        self.displayMode = displayMode
        displayModeStore.applyDisplayMode(displayMode)
        updateSelectedProviderState()
    }

    // MARK: - WebView Hooks (Copilot only)

    /// Page-ready callbacks only fire for Copilot now; ignored for native
    /// providers so they don't accidentally trigger fetches.
    func handlePageReadyChange(for provider: UsageProvider, isReady: Bool) {
        guard provider == .githubCopilot, isReady else { return }
        guard !autoRecoveryInFlight.contains(provider) else { return }
        let isManualRefresh = consumeManualRefreshRequest(for: provider)
        let state = stateManager.getState(for: provider)
        if !isManualRefresh {
            guard state.isAutoRefreshEnabled != true else { return }
        }
        guard !state.isFetching else { return }
        Task {
            await handleCopilotLoginAndFetch(for: provider)
        }
    }

    func handleCookieChange(for provider: UsageProvider) {
        guard provider == .githubCopilot else { return }
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        Task {
            let isLoggedIn = await checkLoginStatusViaWebView(for: provider, using: webViewStore.webView)
            guard isLoggedIn else { return }
            guard !isUsageURL(webViewStore.webView.url, provider: provider) else { return }
            guard canRedirectLogin(for: provider) else { return }
            webViewStore.reloadFromOrigin()
        }
    }

    // MARK: - Core Refresh

    private func refreshAutoEligibleProviders() async {
        let eligibleProviders = stateManager.autoRefreshEligibleProviders(selectedProvider: selectedProvider)
        for provider in eligibleProviders {
            guard !autoRecoveryInFlight.contains(provider) else { continue }
            await refreshSnapshot(for: provider, isManual: false)
        }
    }

    /// Performs a refresh for a provider with the appropriate transport.
    /// `isManual` bypasses the 5-min minimum-poll guard.
    private func refreshSnapshot(for provider: UsageProvider, isManual: Bool) async {
        let currentState = stateManager.getState(for: provider)
        guard !currentState.isFetching else { return }

        // Enforce minimum poll for native providers, except on manual refresh.
        if !isManual, providerEnforcesMinimumPoll(provider) {
            if let last = lastSuccessfulFetchAt[provider],
               Date().timeIntervalSince(last) < ClaudeOAuthConfig.minimumPollInterval {
                return
            }
        }

        switch provider {
        case .chatgptCodex, .claudeCode:
            await refreshNativeProvider(provider)
        case .githubCopilot:
            await refreshCopilot(provider)
        }
    }

    /// True when sub-5-min polling for this provider is harmful to the user's
    /// daily quota (Codex/Claude share quota with the user's CLI sessions).
    private func providerEnforcesMinimumPoll(_ provider: UsageProvider) -> Bool {
        switch provider {
        case .chatgptCodex, .claudeCode:
            return true
        case .githubCopilot:
            return false
        }
    }

    // MARK: - Native Provider Refresh (Codex / Claude)

    private func refreshNativeProvider(_ provider: UsageProvider) async {
        stateManager.setFetching(true, for: provider)
        if provider == selectedProvider { isFetching = true }
        defer {
            stateManager.setFetching(false, for: provider)
            if provider == selectedProvider { isFetching = false }
        }

        do {
            let fetched: UsageSnapshot
            switch provider {
            case .chatgptCodex:
                fetched = try await codexFetcher.fetchUsageSnapshot()
            case .claudeCode:
                fetched = try await claudeFetcher.fetchUsageSnapshot()
            case .githubCopilot:
                return
            }
            let snapshotToSave = fetched.makeSnapshot(for: displayMode)
            try store.saveSnapshot(snapshotToSave)
            displayModeStore.saveCachedDisplayMode(displayMode)
            stateManager.updateAfterSuccessfulFetch(snapshot: snapshotToSave, for: provider)
            lastSuccessfulFetchAt[provider] = snapshotToSave.fetchedAt
            stateManager.setStatusMessage("status.updated".localized(), for: provider)
            if provider == selectedProvider {
                self.snapshot = snapshotToSave
                statusMessage = "status.updated".localized()
            }
            WidgetCenter.shared.reloadTimelines(ofKind: snapshotToSave.provider.widgetKind)
            await ThresholdNotificationManager.shared.checkThresholdsIfNeeded(for: fetched)
        } catch let error as UsageAuthError {
            handleNativeFetchError(error, provider: provider)
        } catch {
            stateManager.setFetchStatus(.failure(error.localizedDescription), for: provider)
            stateManager.setStatusMessage(error.localizedDescription, for: provider)
            if provider == selectedProvider { statusMessage = error.localizedDescription }
        }
    }

    private func handleNativeFetchError(_ error: UsageAuthError, provider: UsageProvider) {
        if error.requiresUserReauth {
            stateManager.setAutoRefreshEnabled(false, for: provider)
        }
        let message = error.errorDescription ?? "fetch failed"
        stateManager.setFetchStatus(.failure(message), for: provider)
        stateManager.setStatusMessage(message, for: provider)
        if provider == selectedProvider { statusMessage = message }
    }

    // MARK: - Copilot Refresh (WebView)

    private func refreshCopilot(_ provider: UsageProvider) async {
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        guard webViewStore.isPageReady else {
            stateManager.setStatusMessage("status.loadingLogin".localized(), for: provider)
            return
        }
        stateManager.setFetching(true, for: provider)
        if provider == selectedProvider { isFetching = true }
        defer {
            stateManager.setFetching(false, for: provider)
            if provider == selectedProvider { isFetching = false }
        }

        do {
            let fetched = try await copilotFetcher.fetchUsageSnapshot(using: webViewStore.webView)
            let snapshotToSave = fetched.makeSnapshot(for: displayMode)
            try store.saveSnapshot(snapshotToSave)
            displayModeStore.saveCachedDisplayMode(displayMode)
            stateManager.updateAfterSuccessfulFetch(snapshot: snapshotToSave, for: provider)
            lastSuccessfulFetchAt[provider] = snapshotToSave.fetchedAt
            autoRecoveryInFlight.remove(provider)
            stateManager.setStatusMessage("status.updated".localized(), for: provider)
            if provider == selectedProvider {
                self.snapshot = snapshotToSave
                statusMessage = "status.updated".localized()
            }
            WidgetCenter.shared.reloadTimelines(ofKind: snapshotToSave.provider.widgetKind)
            await ThresholdNotificationManager.shared.checkThresholdsIfNeeded(for: fetched)
            Task { await fetchCopilotBilling(using: webViewStore.webView) }
        } catch {
            if shouldDisableAutoRefresh(for: provider, error: error) {
                if autoRecoveryInFlight.contains(provider) {
                    autoRecoveryInFlight.remove(provider)
                    stateManager.setAutoRefreshEnabled(false, for: provider)
                } else {
                    autoRecoveryInFlight.insert(provider)
                    webViewPool.getWebViewStore(for: provider).reloadFromOrigin()
                    stateManager.setStatusMessage("status.loadingLogin".localized(), for: provider)
                    if provider == selectedProvider {
                        statusMessage = "status.loadingLogin".localized()
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        await self.waitForCopilotRecoveryFetch(for: provider)
                    }
                    return
                }
            }
            stateManager.setFetchStatus(.failure(error.localizedDescription), for: provider)
            stateManager.setStatusMessage(error.localizedDescription, for: provider)
            if provider == selectedProvider {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func handleCopilotLoginAndFetch(for provider: UsageProvider) async {
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        let isLoggedIn = await checkLoginStatusViaWebView(for: provider, using: webViewStore.webView)
        guard isLoggedIn else {
            stateManager.setStatusMessage("status.loadingLogin".localized(), for: provider)
            if provider == selectedProvider {
                statusMessage = "status.loadingLogin".localized()
            }
            return
        }
        if !isUsageURL(webViewStore.webView.url, provider: provider) {
            webViewStore.reloadFromOrigin()
            return
        }
        await refreshSnapshot(for: provider, isManual: true)
    }

    private func checkLoginStatusViaWebView(for provider: UsageProvider, using webView: WKWebView) async -> Bool {
        switch provider {
        case .githubCopilot:
            return await copilotFetcher.hasValidSession(using: webView)
        case .chatgptCodex, .claudeCode:
            return true
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

    private func shouldDisableAutoRefresh(for provider: UsageProvider, error: Error) -> Bool {
        switch provider {
        case .githubCopilot:
            guard let error = error as? CopilotUsageFetcherError else { return false }
            switch error {
            case .scriptFailed(let message):
                return isLoginRequiredMessage(message)
            case .invalidResponse, .pageNotReady:
                return false
            }
        case .chatgptCodex, .claudeCode:
            return (error as? UsageAuthError)?.requiresUserReauth ?? false
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

    private func waitForCopilotRecoveryFetch(for provider: UsageProvider) async {
        let webViewStore = webViewPool.getWebViewStore(for: provider)
        let deadline = Date().addingTimeInterval(15)
        while !webViewStore.isPageReady && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard webViewStore.isPageReady else {
            autoRecoveryInFlight.remove(provider)
            return
        }
        try? await Task.sleep(for: .seconds(3))
        await handleCopilotLoginAndFetch(for: provider)
        autoRecoveryInFlight.remove(provider)
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

    // MARK: - Copilot Billing

    private func fetchCopilotBilling(using webView: WKWebView) async {
        do {
            let snapshot = try await copilotBillingFetcher.fetchBillingSnapshot(using: webView)
            try TokenUsageSnapshotStore.shared.saveSnapshot(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: TokenUsageProvider.copilot.widgetKind)
        } catch {
            Logger.usage.error("Copilot billing fetch failed: \(error.localizedDescription)")
        }
    }
}
