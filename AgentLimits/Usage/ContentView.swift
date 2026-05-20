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
    @AppStorage(UserDefaultsKeys.menuBarStatusCopilotEnabled) private var menuBarCopilotEnabled = false
    @AppStorage(UserDefaultsKeys.menuBarDashboardCodexEnabled) private var menuBarDashboardCodexEnabled = true
    @AppStorage(UserDefaultsKeys.menuBarDashboardClaudeEnabled) private var menuBarDashboardClaudeEnabled = true
    @AppStorage(UserDefaultsKeys.menuBarDashboardCopilotEnabled) private var menuBarDashboardCopilotEnabled = true
    @State private var orderedProviders: [UsageProvider] = ProviderOrderStore.loadProviderOrder()
    @State private var isShowingClearDataConfirm = false
    @State private var isClearingData = false
    @State private var isWebViewExpanded = false
    @State private var popupWebView: WKWebView?
    @State private var popupWebViewStore: WebViewStore?

    init(viewModel: UsageViewModel, webViewPool: UsageWebViewPool) {
        self.viewModel = viewModel
        self.webViewPool = webViewPool
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
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

                        SettingsFormSection(title: "settings.providerOrder".localized()) {
                            List {
                                ForEach(orderedProviders, id: \.self) { provider in
                                    HStack(spacing: 8) {
                                        Image(systemName: "line.3.horizontal")
                                            .foregroundStyle(.secondary)
                                        Text(provider.displayName)
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                                .onMove { source, destination in
                                    orderedProviders.move(fromOffsets: source, toOffset: destination)
                                    ProviderOrderStore.saveProviderOrder(orderedProviders)
                                }
                            }
                            .listStyle(.bordered(alternatesRowBackgrounds: true))
                            .frame(height: CGFloat(orderedProviders.count) * 34)
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
                }
                .padding(DesignTokens.Spacing.large)
                .padding(.bottom, webViewPanelCollapsedHeight + DesignTokens.Spacing.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(!isWebViewExpanded)

                if isWebViewExpanded {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture {
                            collapseWebViewPanel()
                        }
                        .transition(.opacity)
                }

                webViewPanel(totalHeight: geometry.size.height)
            }
        }
        .onChange(of: refreshIntervalMinutes) { _, _ in
            // Restart auto-refresh and notify widgets when interval changes.
            viewModel.restartAutoRefresh()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onAppear {
            orderedProviders = ProviderOrderStore.loadProviderOrder()
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
        Group {
            Toggle("settings.showInMenuBar".localized(), isOn: menuBarEnabledBinding)
                .toggleStyle(.checkbox)
            Toggle("settings.showMenuDashboard".localized(), isOn: menuBarDashboardEnabledBinding)
                .toggleStyle(.checkbox)
        }
    }

    private var menuBarEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    return menuBarCodexEnabled
                case .claudeCode:
                    return menuBarClaudeEnabled
                case .githubCopilot:
                    return menuBarCopilotEnabled
                }
            },
            set: { newValue in
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    menuBarCodexEnabled = newValue
                case .claudeCode:
                    menuBarClaudeEnabled = newValue
                case .githubCopilot:
                    menuBarCopilotEnabled = newValue
                }
            }
        )
    }

    private var menuBarDashboardEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    return menuBarDashboardCodexEnabled
                case .claudeCode:
                    return menuBarDashboardClaudeEnabled
                case .githubCopilot:
                    return menuBarDashboardCopilotEnabled
                }
            },
            set: { newValue in
                switch viewModel.selectedProvider {
                case .chatgptCodex:
                    menuBarDashboardCodexEnabled = newValue
                case .claudeCode:
                    menuBarDashboardClaudeEnabled = newValue
                case .githubCopilot:
                    menuBarDashboardCopilotEnabled = newValue
                }
            }
        )
    }

    private var webViewPanelCollapsedHeight: CGFloat { 42 }

    private func webViewPanel(totalHeight: CGFloat) -> some View {
        let panelPadding = DesignTokens.Spacing.large
        let expandedHeight = max(
            webViewPanelCollapsedHeight,
            totalHeight - (panelPadding * 2)
        )

        return VStack(spacing: 0) {
            webViewPanelHandle

            if isWebViewExpanded {
                Divider()
                loginWebViewSection
                    .padding(DesignTokens.Spacing.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: isWebViewExpanded ? expandedHeight : webViewPanelCollapsedHeight,
            alignment: .top
        )
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.medium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.medium)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
        .shadow(color: .black.opacity(isWebViewExpanded ? 0.16 : 0.08), radius: isWebViewExpanded ? 10 : 4, y: 2)
        .padding(.horizontal, panelPadding)
        .padding(.bottom, panelPadding)
        .animation(.easeInOut(duration: 0.2), value: isWebViewExpanded)
    }

    private var webViewPanelHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isWebViewExpanded.toggle()
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.small) {
                Image(systemName: isWebViewExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.bold())
                Text("content.login".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(viewModel.selectedProvider.displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, DesignTokens.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("content.login".localized()))
    }

    private func collapseWebViewPanel() {
        guard isWebViewExpanded else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isWebViewExpanded = false
        }
    }

    private var loginWebViewSection: some View {
        Group {
            switch viewModel.selectedProvider {
            case .chatgptCodex, .claudeCode:
                NativeAuthStatusView(
                    provider: viewModel.selectedProvider,
                    snapshot: viewModel.snapshot,
                    fetchStatuses: viewModel.fetchStatuses,
                    onRefresh: { viewModel.fetchNow() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DesignTokens.Spacing.medium)
            case .githubCopilot:
                ZStack {
                    let store = webViewPool.getWebViewStore(for: .githubCopilot)
                    WebViewRepresentable(store: store)
                        .onReceive(store.$popupWebView) { popup in
                            if let popup {
                                popupWebView = popup
                                popupWebViewStore = store
                                store.onPopupNavigationFinished = { [weak viewModel] _ in
                                    guard let viewModel else { return false }
                                    return await viewModel.checkLoginStatus(for: store.provider)
                                }
                            } else if popupWebViewStore === store {
                                popupWebView = nil
                                popupWebViewStore = nil
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .cornerRadius(DesignTokens.CornerRadius.medium)
            }
        }
    }

}

// MARK: - Native Auth Status

/// Status panel shown in place of the WebView for native (CLI-credential)
/// providers. Surfaces login state, subscription badge, and a re-auth button
/// that detached-spawns the provider CLI to refresh the keychain item.
private struct NativeAuthStatusView: View {
    let provider: UsageProvider
    let snapshot: UsageSnapshot?
    let fetchStatuses: [UsageProvider: ProviderFetchStatus]
    let onRefresh: () -> Void

    @State private var isLoggedIn: Bool = false
    @State private var didTriggerReauth: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(spacing: DesignTokens.Spacing.small) {
                Image(systemName: isLoggedIn ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(isLoggedIn ? Color.green : Color.orange)
                Text(headlineText)
                    .font(.headline)
                Spacer()
                if let plan = snapshot?.planType, !plan.isEmpty {
                    Text(plan.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            if let statusText = lastFetchText {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(explanationText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DesignTokens.Spacing.small) {
                Button(reauthButtonLabel) {
                    triggerReauth()
                }
                .controlSize(.regular)
                Button("nativeAuth.refresh".localized()) {
                    onRefresh()
                }
                .controlSize(.regular)
                Spacer()
                if didTriggerReauth {
                    Text("nativeAuth.waitingForLogin".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear(perform: refreshLoginState)
        .onChange(of: snapshot?.fetchedAt) { _, _ in
            refreshLoginState()
        }
    }

    private var headlineText: String {
        isLoggedIn
            ? "nativeAuth.loggedIn".localized(provider.displayName)
            : "nativeAuth.notLoggedIn".localized(provider.displayName)
    }

    private var explanationText: String {
        switch provider {
        case .chatgptCodex:
            return "nativeAuth.explanationCodex".localized()
        case .claudeCode:
            return "nativeAuth.explanationClaude".localized()
        case .githubCopilot:
            return ""
        }
    }

    private var reauthButtonLabel: String {
        switch provider {
        case .chatgptCodex:
            return "nativeAuth.runCodexLogin".localized()
        case .claudeCode:
            return "nativeAuth.runClaudeLogin".localized()
        case .githubCopilot:
            return ""
        }
    }

    private var lastFetchText: String? {
        guard let status = fetchStatuses[provider] else { return nil }
        switch status {
        case .success(let date):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "usage.updated".localized() + formatter.string(from: date)
        case .failure(let message):
            return message
        case .notFetched:
            return "status.notFetched".localized()
        }
    }

    private func refreshLoginState() {
        switch provider {
        case .chatgptCodex:
            isLoggedIn = CodexUsageFetcher().hasValidSession()
        case .claudeCode:
            isLoggedIn = ClaudeUsageFetcher().hasValidSession()
        case .githubCopilot:
            isLoggedIn = false
        }
    }

    private func triggerReauth() {
        let launched: Bool
        switch provider {
        case .chatgptCodex:
            launched = ClaudeCLILocator.launchCodexLogin()
        case .claudeCode:
            launched = ClaudeCLILocator.launchClaudeLogin()
        case .githubCopilot:
            launched = false
        }
        didTriggerReauth = launched
        // Poll the credential store every 5s for up to 2 minutes for the
        // rotated token to appear, then auto-trigger a fetch.
        guard launched else { return }
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(5))
                refreshLoginState()
                if isLoggedIn {
                    didTriggerReauth = false
                    onRefresh()
                    return
                }
            }
            didTriggerReauth = false
        }
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
                if snapshot.provider == .githubCopilot {
                    UsageWindowRow(title: "content.month".localized(), window: snapshot.primaryWindow, displayMode: displayMode)
                } else {
                    UsageWindowRow(title: "content.5hours".localized(), window: snapshot.primaryWindow, displayMode: displayMode)
                    UsageWindowRow(title: "content.week".localized(), window: snapshot.secondaryWindow, displayMode: displayMode)
                }
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
