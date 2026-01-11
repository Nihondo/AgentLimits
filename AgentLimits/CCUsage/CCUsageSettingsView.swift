// MARK: - CCUsageSettingsView.swift
// Settings UI for configuring ccusage token usage tracking.
// Allows users to enable/disable providers and configure additional CLI arguments.

import SwiftUI
import WidgetKit

// MARK: - CCUsage Settings View

/// Settings view for configuring ccusage token usage tracking
@MainActor
struct CCUsageSettingsView: View {
    @ObservedObject private var viewModel: TokenUsageViewModel
    @State private var selectedProvider: TokenUsageProvider = .codex
    @AppStorage(
        AppGroupConfig.tokenUsageRefreshIntervalMinutesKey,
        store: AppGroupDefaults.shared
    ) private var refreshIntervalMinutes: Int = RefreshIntervalConfig.defaultMinutes

    init(viewModel: TokenUsageViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SettingsScrollContainer {
            headerView

            Form {
                SettingsFormSection {
                    LabeledContent("ccusage.provider".localized()) {
                        providerPicker
                    }
                    LabeledContent("refreshInterval.label".localized()) {
                        RefreshIntervalPickerRow(showsLabel: false, refreshIntervalMinutes: $refreshIntervalMinutes)
                    }
                }

                SettingsFormSection(title: "ccusage.settings".localized()) {
                    settingsSection
                }

                SettingsFormSection(title: "ccusage.status".localized()) {
                    statusSection
                    lastResultView
                }

                SettingsFormSection(footerText: "ccusage.credits.body".localized()) {
                    creditsSection
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: refreshIntervalMinutes) { _, _ in
            viewModel.restartAutoRefresh()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        SettingsHeaderView(
            titleText: "ccusage.title".localized(),
            descriptionText: "ccusage.description".localized()
        )
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("", selection: $selectedProvider) {
            ForEach(TokenUsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .labelsHidden()
        .accessibilityLabel(Text("ccusage.provider".localized()))
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        Group {
            if let settings = viewModel.settings[selectedProvider] {
                ProviderSettingsView(
                    settings: settings,
                    isFetching: viewModel.isFetching[selectedProvider] ?? false,
                    onEnabledChange: { newEnabled in
                        var updated = settings
                        updated.isEnabled = newEnabled
                        viewModel.updateSettings(updated)
                    },
                    onUpdate: { updatedSettings in
                        viewModel.updateSettings(updatedSettings)
                    },
                    onTest: {
                        Task {
                            await viewModel.refreshNow(for: selectedProvider)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            ForEach(TokenUsageProvider.allCases) { provider in
                providerStatusRow(for: provider)
            }
        }
    }

    // MARK: - Credits Section

    /// Credits section showing links to ccusage website and repository.
    /// Uses pre-validated static URL constants for safety.
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("ccusage.credits.title".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let siteURL = CCUsageLinks.siteURL {
                Link(
                    "ccusage.credits.site".localized(),
                    destination: siteURL
                )
                .font(.caption)
            }

            if let repoURL = CCUsageLinks.repoURL {
                Link(
                    "ccusage.credits.repo".localized(),
                    destination: repoURL
                )
                .font(.caption)
            }
        }
    }

    private func providerStatusRow(for provider: TokenUsageProvider) -> some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            SettingsStatusIndicator(
                text: provider.displayName,
                level: statusLevel(for: provider)
            )
            Spacer()
            if let settings = viewModel.settings[provider], settings.isEnabled {
                Text(viewModel.statusMessages[provider] ?? "tokenUsage.notFetched".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("ccusage.disabled".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastResultView: some View {
        Group {
            if let snapshot = viewModel.snapshots[selectedProvider] {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ccusage.lastResult".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        // Show month totals from the latest snapshot.
                        Label(TokenUsageFormatter.formatCost(snapshot.thisMonth.costUSD), systemImage: "dollarsign.circle")
                            .font(.footnote)
                        Spacer()
                        Text(TokenUsageFormatter.formatTokens(snapshot.thisMonth.totalTokens))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private func statusLevel(for provider: TokenUsageProvider) -> SettingsStatusLevel {
        // Gray when disabled, green when fetched, orange while enabled but no snapshot yet.
        guard let settings = viewModel.settings[provider], settings.isEnabled else {
            return .inactive
        }
        if viewModel.snapshots[provider] != nil {
            return .success
        }
        return .warning
    }

}

// MARK: - Provider Settings View

/// Settings configuration for a single provider
private struct ProviderSettingsView: View {
    let settings: CCUsageSettings
    let isFetching: Bool
    let onEnabledChange: (Bool) -> Void
    let onUpdate: (CCUsageSettings) -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("ccusage.enabled".localized(), isOn: enabledBinding)

            if settings.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ccusage.command".localized())
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(settings.displayCommand)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                LabeledContent("ccusage.additionalArgs".localized()) {
                    TextField(
                        "",
                        text: additionalArgsBinding,
                        prompt: Text("ccusage.additionalArgsPlaceholder".localized())
                    )
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("ccusage.additionalArgs".localized()))
                }

                HStack {
                    Button("ccusage.testNow".localized()) {
                        onTest()
                    }
                    .disabled(isFetching)

                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                onEnabledChange(newValue)
            }
        )
    }

    private var additionalArgsBinding: Binding<String> {
        Binding(
            get: { settings.additionalArgs },
            set: { newValue in
                onUpdate(CCUsageSettings(
                    provider: settings.provider,
                    isEnabled: settings.isEnabled,
                    additionalArgs: newValue
                ))
            }
        )
    }
}

// MARK: - Preview

#Preview {
    CCUsageSettingsView(viewModel: TokenUsageViewModel())
}
