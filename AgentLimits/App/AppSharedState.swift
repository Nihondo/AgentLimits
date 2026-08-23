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
    let customUsageViewModel: CustomUsageViewModel

    /// 設定ウィンドウクローズ時のコールバック（AppDelegate が設定する）
    var onSettingsWindowClosed: (() -> Void)?

    private var isStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let pool = UsageWebViewPool()
        self.webViewPool = pool
        self.viewModel = UsageViewModel(webViewPool: pool)
        self.tokenUsageViewModel = TokenUsageViewModel()
        self.customUsageViewModel = CustomUsageViewModel()
        observePageReadyChanges()
        observeCookieChanges()
        let storedMode = UsageDisplayMode.makeSelectableMode(
            from: UserDefaults.standard.string(forKey: UserDefaultsKeys.displayMode)
        )
        viewModel.updateDisplayMode(storedMode)
        if !Self.isRunningUnitTests {
            startBackgroundRefresh()

            // Initialize WakeUpScheduler to sync LaunchAgents on startup
            _ = WakeUpScheduler.shared

            // Refresh widgets once on app launch.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Starts background refresh and loads WebViews (called once)
    func startBackgroundRefresh() {
        guard !isStarted else { return }
        isStarted = true
        loadWebViews()
        viewModel.startAutoRefresh()
        tokenUsageViewModel.startAutoRefresh()
        customUsageViewModel.startAutoRefresh()
    }

    /// Applies the background WebView policy for providers with fetch history.
    private func loadWebViews() {
        webViewPool.applyBackgroundPolicy(
            activeProviders: Set(viewModel.backgroundActiveProviders)
        )
    }

    /// 設定画面で操作するため、選択中プロバイダーのWebViewを復帰する。
    func resumeWebViewForSettings() {
        webViewPool.resume(viewModel.selectedProvider)
    }

    /// 設定画面を閉じた後、取得実績のないWebViewを停止状態に戻す。
    func applyBackgroundPolicyOnSettingsClose() {
        webViewPool.applyBackgroundPolicy(
            activeProviders: Set(viewModel.backgroundActiveProviders)
        )
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

    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
