// MARK: - ContentView.swift
// Main settings window UI for viewing and refreshing usage data.
// Displays usage summary, provider selector, and embedded WebView for login.

import SwiftUI
import WebKit
import WidgetKit

// MARK: - Main Content View

/// Settings window content displaying usage data and login WebView
struct ContentView: View {
    @ObservedObject private var viewModel: UsageViewModel
    private let webViewPool: UsageWebViewPool
    @AppStorage(UserDefaultsKeys.displayMode) private var displayMode: UsageDisplayMode = .used
    @AppStorage(
        AppGroupConfig.usageRefreshIntervalMinutesKey,
        store: AppGroupDefaults.shared
    ) private var refreshIntervalMinutes: Int = RefreshIntervalConfig.defaultMinutes
    @AppStorage(UserDefaultsKeys.menuBarStatusCodexEnabled) private var menuBarCodexEnabled = false
    @AppStorage(UserDefaultsKeys.menuBarStatusClaudeEnabled) private var menuBarClaudeEnabled = false
    @State private var isShowingClearDataConfirm = false
    @State private var isClearingData = false
    @State private var popupWebView: WKWebView?
    @State private var popupWebViewStore: WebViewStore?

    init(viewModel: UsageViewModel, webViewPool: UsageWebViewPool) {
        self.viewModel = viewModel
        self.webViewPool = webViewPool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            headerView

            Form {
                SettingsFormSection {
                    LabeledContent("content.provider".localized()) {
                        providerPicker
                    }
                    LabeledContent("refreshInterval.label".localized()) {
                        RefreshIntervalPickerRow(showsLabel: false, refreshIntervalMinutes: $refreshIntervalMinutes)
                    }
                }

                SettingsFormSection {
                    menuBarToggleRow
                }

                SettingsFormSection(title: "content.usageSummary".localized()) {
                    UsageSummaryView(
                        snapshot: viewModel.snapshot,
                        displayMode: displayMode,
                        fetchStatuses: viewModel.fetchStatuses
                    )
                }

                SettingsFormSection {
                    controlView
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Divider()
                Text("content.login".localized())
                    .font(.headline)
                loginWebViewSection
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
        .padding(DesignTokens.Spacing.large)
        .onChange(of: refreshIntervalMinutes) { _, _ in
            // Restart auto-refresh and notify widgets when interval changes.
            viewModel.restartAutoRefresh()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .confirmationDialog(
            "content.clearDataConfirmTitle".localized(),
            isPresented: $isShowingClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button("content.clearDataConfirmAction".localized(), role: .destructive) {
                Task {
                    // Clear all website data and force re-login.
                    isClearingData = true
                    await webViewPool.clearWebsiteData()
                    isClearingData = false
                }
            }
            Button("content.clearDataCancel".localized(), role: .cancel) {}
        } message: {
            Text("content.clearDataConfirmMessage".localized())
        }
        .sheet(
            isPresented: Binding(
                get: { popupWebView != nil },
                set: { isPresented in
                    if !isPresented {
                        // Close popup and release WebView when sheet dismissed.
                        popupWebViewStore?.closePopupWebView()
                        popupWebViewStore = nil
                        popupWebView = nil
                    }
                }
            )
        ) {
            if let popup = popupWebView {
                PopupWebViewSheet(
                    webView: popup,
                    onClose: {
                        // Explicit close action from sheet UI.
                        popupWebViewStore?.closePopupWebView()
                        popupWebViewStore = nil
                        popupWebView = nil
                    }
                )
            }
        }
    }

    private var headerView: some View {
        SettingsHeaderView(
            titleText: "content.usageLimit".localized(),
            descriptionText: "content.autoRefresh".localized(refreshIntervalMinutes)
        )
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("", selection: $viewModel.selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName)
                    .tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .labelsHidden()
        .accessibilityLabel(Text("content.provider".localized()))
    }

    private var controlView: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            HStack(spacing: DesignTokens.Spacing.medium) {
                Button("content.refreshNow".localized()) {
                    viewModel.fetchNow()
                }
                .disabled(viewModel.isFetching)
                .settingsButtonStyle(.primary)

                if viewModel.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("content.clearData".localized(), role: .destructive) {
                    isShowingClearDataConfirm = true
                }
                .disabled(isClearingData)
                .settingsButtonStyle(.destructive)

                if isClearingData {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var menuBarToggleRow: some View {
        Toggle("settings.showInMenuBar".localized(), isOn: menuBarEnabledBinding)
            .toggleStyle(.checkbox)
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    return menuBarCodexEnabled
                case .claudeCode:
                    return menuBarClaudeEnabled
                }
            },
            set: { newValue in
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    menuBarCodexEnabled = newValue
                case .claudeCode:
                    menuBarClaudeEnabled = newValue
                }
            }
        )
    }

    private var loginWebViewSection: some View {
        ZStack {
            ForEach(UsageProvider.allCases) { provider in
                let store = webViewPool.getWebViewStore(for: provider)
                WebViewRepresentable(store: store)
                    .onReceive(store.$popupWebView) { popup in
                        if let popup {
                            popupWebView = popup
                            popupWebViewStore = store
                            // Set up login check callback for auto-close.
                            store.onPopupNavigationFinished = { [weak viewModel] _ in
                                guard let viewModel else { return false }
                                return await viewModel.checkLoginStatus(for: store.provider)
                            }
                        } else {
                            // Close sheet when popup is dismissed programmatically.
                            if popupWebViewStore === store {
                                popupWebView = nil
                                popupWebViewStore = nil
                            }
                        }
                    }
                .opacity(viewModel.selectedProvider == provider ? 1 : 0)
                .allowsHitTesting(viewModel.selectedProvider == provider)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .cornerRadius(DesignTokens.CornerRadius.medium)
    }

}

// MARK: - Popup WebView Sheet

/// Sheet for displaying popup windows (e.g., OAuth login flows)
private struct PopupWebViewSheet: View {
    let webView: WKWebView
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("content.popupClose".localized()) {
                    onClose()
                }
            }
            WebViewContainer(webView: webView)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 640)
    }
}

/// NSViewRepresentable wrapper for displaying WKWebView
private struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}

// MARK: - Usage Summary Views

/// Displays the current usage snapshot with 5-hour and weekly windows
private struct UsageSummaryView: View {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    let snapshot: UsageSnapshot?
    let displayMode: UsageDisplayMode
    let fetchStatuses: [UsageProvider: ProviderFetchStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            statusSection

            Divider()
                .padding(.vertical, 2)

            usageSection
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            ForEach(UsageProvider.allCases) { provider in
                HStack(spacing: DesignTokens.Spacing.small) {
                    SettingsStatusIndicator(
                        text: provider.displayName,
                        level: statusLevel(for: provider)
                    )
                    Spacer()
                    Text(statusText(for: provider))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usageSection: some View {
        Group {
            if let snapshot {
                UsageWindowRow(title: "content.5hours".localized(), window: snapshot.primaryWindow, displayMode: displayMode)
                UsageWindowRow(title: "content.week".localized(), window: snapshot.secondaryWindow, displayMode: displayMode)
            } else {
                Text("content.notFetched".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusLevel(for provider: UsageProvider) -> SettingsStatusLevel {
        switch fetchStatuses[provider] ?? .notFetched {
        case .success:
            return .success
        case .failure:
            return .error
        case .notFetched:
            return .warning
        }
    }

    private func statusText(for provider: UsageProvider) -> String {
        switch fetchStatuses[provider] ?? .notFetched {
        case .success(let fetchedAt):
            return "usage.updated".localized() + Self.timeFormatter.string(from: fetchedAt)
        case .failure(let message):
            return message
        case .notFetched:
            return "status.notFetched".localized()
        }
    }
}

/// Displays a single usage window row with percentage and reset time
private struct UsageWindowRow: View {
    let title: String
    let window: UsageWindow?
    let displayMode: UsageDisplayMode

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.body)
            Spacer()
            HStack(spacing: 6) {
                Text(windowPercentText)
                    .font(.body)
                    .monospacedDigit()
                Text("•")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("content.reset".localized())
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let resetAt = window?.resetAt {
                    Text(resetAt, style: .relative)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("-")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var windowPercentText: String {
        let percent = window.map { displayMode.displayPercent(from: $0.usedPercent, window: $0) }
        return UsagePercentFormatter.formatPercentText(percent)
    }
}

#Preview {
    let pool = UsageWebViewPool()
    let viewModel = UsageViewModel(webViewPool: pool)
    return ContentView(viewModel: viewModel, webViewPool: pool)
}
