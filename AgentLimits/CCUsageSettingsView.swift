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
        store: UserDefaults(suiteName: AppGroupConfig.groupId)
    ) private var refreshIntervalMinutes: Int = RefreshIntervalConfig.defaultMinutes

    init(viewModel: TokenUsageViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()

            providerPickerRow
            settingsSection
            Divider()
            statusSection
            Divider()
            creditsSection

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes)
        }
        .onChange(of: refreshIntervalMinutes) { _, _ in
            viewModel.restartAutoRefresh()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ccusage.title".localized())
                .font(.title2)
                .bold()
            Text("ccusage.description".localized())
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
        Picker("ccusage.provider".localized(), selection: $selectedProvider) {
            ForEach(TokenUsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("ccusage.status".localized())
                .font(.headline)

            ForEach(TokenUsageProvider.allCases) { provider in
                providerStatusRow(for: provider)
            }

            lastResultView
        }
    }

    // MARK: - Credits Section

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ccusage.credits.title".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("ccusage.credits.body".localized())
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(
                "ccusage.credits.site".localized(),
                destination: URL(string: "https://ccusage.com/")!
            )
            .font(.caption)

            Link(
                "ccusage.credits.repo".localized(),
                destination: URL(string: "https://github.com/ryoppippi/ccusage")!
            )
            .font(.caption)
        }
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { RefreshIntervalConfig.normalizedMinutes(refreshIntervalMinutes) },
            set: { newValue in
                refreshIntervalMinutes = RefreshIntervalConfig.normalizedMinutes(newValue)
            }
        )
    }

    private func providerStatusRow(for provider: TokenUsageProvider) -> some View {
        HStack {
            Circle()
                .fill(statusColor(for: provider))
                .frame(width: 8, height: 8)
            Text(provider.displayName)
                .font(.body)
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
                        Label(formatCost(snapshot.thisMonth.costUSD), systemImage: "dollarsign.circle")
                            .font(.footnote)
                        Spacer()
                        Text(formatTokens(snapshot.thisMonth.totalTokens))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(for provider: TokenUsageProvider) -> Color {
        guard let settings = viewModel.settings[provider], settings.isEnabled else {
            return .gray
        }
        if viewModel.snapshots[provider] != nil {
            return .green
        }
        return .orange
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$ %.2f", cost)
    }

    private func formatTokens(_ tokens: Int) -> String {
        let kTokens = Double(tokens) / 1000.0
        if kTokens >= 1000 {
            return String(format: "%.1fM Tokens", kTokens / 1000.0)
        } else if kTokens >= 1 {
            return String(format: "%.0fK Tokens", kTokens)
        } else {
            return "\(tokens) Tokens"
        }
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("ccusage.additionalArgs".localized())
                        .font(.body)
                        .foregroundStyle(.secondary)
                    TextField("ccusage.additionalArgsPlaceholder".localized(), text: additionalArgsBinding)
                        .textFieldStyle(.roundedBorder)
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
