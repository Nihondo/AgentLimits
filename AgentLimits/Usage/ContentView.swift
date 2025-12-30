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
        store: UserDefaults(suiteName: AppGroupConfig.groupId)
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
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()

            providerPickerRow
            menuBarToggleRow
            UsageSummaryView(snapshot: viewModel.snapshot, displayMode: displayMode)
            controlView
            Divider()
            Text("content.login".localized())
                .font(.headline)
            ZStack {
                ForEach(UsageProvider.allCases) { provider in
                    let store = webViewPool.getWebViewStore(for: provider)
                    WebViewRepresentable(store: store)
                        .onReceive(store.$popupWebView) { popup in
                            guard let popup else { return }
                            popupWebView = popup
                            popupWebViewStore = store
                        }
                    .opacity(viewModel.selectedProvider == provider ? 1 : 0)
                    .allowsHitTesting(viewModel.selectedProvider == provider)
                }
            }
            .frame(minHeight: 360)
            .cornerRadius(8)
        }
        .padding()
        .onAppear {
            // Normalize refresh interval on launch.
            refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("content.usageLimit".localized())
                .font(.title2)
                .bold()
            Text("content.autoRefresh".localized(refreshIntervalMinutes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Provider Picker

    private var providerPickerRow: some View {
        HStack(spacing: 12) {
            providerPicker
            Spacer(minLength: 0)
            refreshIntervalMenu
        }
    }

    private var providerPicker: some View {
        Picker("content.provider".localized(), selection: $viewModel.selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName)
                    .tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    private var refreshIntervalMenu: some View {
        HStack(spacing: 6) {
            Text("refreshInterval.label".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker(
                "refreshInterval.label".localized(),
                selection: refreshIntervalBinding
            ) {
                ForEach(RefreshIntervalConfig.supportedMinutes, id: \.self) { minutes in
                    Text("refreshInterval.minutesFormat".localized(minutes))
                        .tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var controlView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button("content.refreshNow".localized()) {
                    viewModel.fetchNow()
                }
                .disabled(viewModel.isFetching)

                if viewModel.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("content.clearData".localized(), role: .destructive) {
                    isShowingClearDataConfirm = true
                }
                .disabled(isClearingData)

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
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
    }

    private var menuBarToggleRow: some View {
        HStack {
            Toggle("settings.showInMenuBar".localized(), isOn: menuBarEnabledBinding)
                .toggleStyle(.checkbox)
            Spacer()
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

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes) },
            set: { newValue in
                refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(newValue)
            }
        )
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
    let snapshot: UsageSnapshot?
    let displayMode: UsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("content.latestUsage".localized())
                .font(.headline)

            if let snapshot {
                UsageWindowRow(title: "content.5hours".localized(), window: snapshot.primaryWindow, displayMode: displayMode)
                UsageWindowRow(title: "content.week".localized(), window: snapshot.secondaryWindow, displayMode: displayMode)
                HStack(spacing: 6) {
                    Text("content.updated".localized())
                    Text(snapshot.fetchedAt, style: .relative)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("content.notFetched".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
    }
}

/// Displays a single usage window row with percentage and reset time
private struct UsageWindowRow: View {
    let title: String
    let window: UsageWindow?
    let displayMode: UsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer()
                Text(windowPercentText)
                    .font(.body)
                    .monospacedDigit()
            }
            if let window {
                HStack(spacing: 6) {
                    Text("content.reset".localized())
                    if let resetAt = window.resetAt {
                        Text(resetAt, style: .relative)
                    } else {
                        Text("-")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var windowPercentText: String {
        let percent = window.map { displayMode.displayPercent(from: $0.usedPercent) }
        return UsagePercentFormatter.formatPercentText(percent)
    }
}

#Preview {
    let pool = UsageWebViewPool()
    let viewModel = UsageViewModel(webViewPool: pool)
    return ContentView(viewModel: viewModel, webViewPool: pool)
}
