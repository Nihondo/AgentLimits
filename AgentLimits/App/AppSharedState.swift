// MARK: - AppSharedState.swift
// Shared application state for menu bar and settings window.
// Manages WebView pool, view model, and page-ready observation.

import Combine
import Foundation
import WidgetKit

// MARK: - App Shared State

/// Shared state container for the entire application.
/// Initializes WebView pool, view model, and observes page-ready changes.
@MainActor
final class AppSharedState: ObservableObject {
    static let shared = AppSharedState()

    let webViewPool: UsageWebViewPool
    let viewModel: UsageViewModel
    let tokenUsageViewModel: TokenUsageViewModel

    private var isStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let pool = UsageWebViewPool()
        self.webViewPool = pool
        self.viewModel = UsageViewModel(webViewPool: pool)
        self.tokenUsageViewModel = TokenUsageViewModel()
        observePageReadyChanges()
        observeCookieChanges()
        let storedMode = UserDefaults.standard.string(forKey: UserDefaultsKeys.displayMode)
            .flatMap { UsageDisplayMode(rawValue: $0) } ?? .used
        viewModel.updateDisplayMode(storedMode)
        startBackgroundRefresh()

        // Initialize WakeUpScheduler to sync LaunchAgents on startup
        _ = WakeUpScheduler.shared

        // Refresh widgets once on app launch.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Starts background refresh and loads WebViews (called once)
    func startBackgroundRefresh() {
        guard !isStarted else { return }
        isStarted = true
        loadWebViews()
        viewModel.startAutoRefresh()
        tokenUsageViewModel.startAutoRefresh()
    }

    /// Preloads WebViews for all providers
    private func loadWebViews() {
        for provider in UsageProvider.allCases {
            webViewPool.getWebViewStore(for: provider).loadIfNeeded()
        }
    }

    /// Sets up Combine subscriptions to observe page-ready state changes
    private func observePageReadyChanges() {
        for provider in UsageProvider.allCases {
            let store = webViewPool.getWebViewStore(for: provider)
            store.$isPageReady
                .removeDuplicates()
                .sink { [weak self] isReady in
                    self?.viewModel.handlePageReadyChange(for: provider, isReady: isReady)
                }
                .store(in: &cancellables)
        }
    }

    /// Observes cookie changes to trigger login-based navigation
    private func observeCookieChanges() {
        for provider in UsageProvider.allCases {
            let store = webViewPool.getWebViewStore(for: provider)
            store.$cookieChangeToken
                .sink { [weak self] _ in
                    self?.viewModel.handleCookieChange(for: provider)
                }
                .store(in: &cancellables)
        }
    }
}
