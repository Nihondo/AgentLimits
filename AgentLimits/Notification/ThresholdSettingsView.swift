// MARK: - ThresholdSettingsView.swift
// Settings UI for configuring usage threshold notifications.
// Allows users to set per-provider, per-window notification thresholds.

import SwiftUI
import WidgetKit

// MARK: - Threshold Settings View

/// Settings view for configuring threshold notifications
@MainActor
struct ThresholdSettingsView: View {
    @ObservedObject private var manager: ThresholdNotificationManager
    @State private var selectedProvider: UsageProvider = .chatgptCodex

    init(manager: ThresholdNotificationManager) {
        self.manager = manager
    }

    var body: some View {
        SettingsScrollContainer {
            headerView

            Form {
                if !manager.isNotificationAuthorized {
                    SettingsFormSection {
                        authorizationSection
                    }
                }

                SettingsFormSection {
                    LabeledContent("notification.provider".localized()) {
                        providerPicker
                    }
                }

                SettingsFormSection(title: "notification.primaryWindow".localized()) {
                    thresholdSection(
                        settings: manager.getSettings(for: selectedProvider).primaryWindow,
                        windowKind: .primary
                    )
                }

                SettingsFormSection(title: "notification.secondaryWindow".localized()) {
                    thresholdSection(
                        settings: manager.getSettings(for: selectedProvider).secondaryWindow,
                        windowKind: .secondary
                    )
                }

                SettingsFormSection {
                    HStack {
                        Spacer()
                        Button("notification.resetDefaults".localized()) {
                            manager.resetSettings(for: selectedProvider)
                            reloadUsageWidgets(for: selectedProvider)
                        }
                        .settingsButtonStyle(.secondary)
                    }
                }


                SettingsFormSection(title: "notification.colors".localized()) {
                    UsageColorSettingsSection()
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    // MARK: - Header

    private var headerView: some View {
        SettingsHeaderView(
            titleText: "notification.title".localized(),
            descriptionText: "notification.description".localized()
        )
    }

    // MARK: - Authorization Section

    private var authorizationSection: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("notification.authorization".localized())
                .font(.subheadline)
            Spacer()
            Button("notification.requestAuth".localized()) {
                Task {
                    await manager.requestNotificationAuthorization()
                }
            }
            .settingsButtonStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.small)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(DesignTokens.CornerRadius.medium)
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("", selection: $selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .labelsHidden()
        .accessibilityLabel(Text("notification.provider".localized()))
    }

    // MARK: - Threshold Section

    private enum ThresholdWindowKind {
        case primary
        case secondary
    }

    private func thresholdSection(
        settings: WindowThresholdSettings,
        windowKind: ThresholdWindowKind
    ) -> some View {
        WindowThresholdView(
            settings: settings,
            onCommit: {
                reloadUsageWidgets(for: selectedProvider)
            },
            onUpdate: { newWindowSettings in
                var updated = manager.getSettings(for: selectedProvider)
                switch windowKind {
                case .primary:
                    updated.primaryWindow = newWindowSettings
                case .secondary:
                    updated.secondaryWindow = newWindowSettings
                }
                manager.updateSettings(updated)
            }
        )
    }

    private func reloadUsageWidgets(for provider: UsageProvider) {
        WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
    }
}

// MARK: - Window Threshold View

/// Configuration view for a single window's threshold settings
private struct WindowThresholdView: View {
    let settings: WindowThresholdSettings
    let onCommit: () -> Void
    let onUpdate: (WindowThresholdSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            ThresholdLevelRow(
                title: "notification.warning".localized(),
                settings: settings.warning,
                onCommit: onCommit,
                onUpdate: { newLevelSettings in
                    var updated = settings
                    var normalized = newLevelSettings
                    normalized.thresholdPercent = min(
                        max(normalized.thresholdPercent, 1),
                        settings.danger.thresholdPercent
                    )
                    updated.warning = normalized
                    onUpdate(updated)
                }
            )

            Divider()

            ThresholdLevelRow(
                title: "notification.danger".localized(),
                settings: settings.danger,
                onCommit: onCommit,
                onUpdate: { newLevelSettings in
                    var updated = settings
                    var normalized = newLevelSettings
                    normalized.thresholdPercent = max(
                        min(normalized.thresholdPercent, 100),
                        settings.warning.thresholdPercent
                    )
                    updated.danger = normalized
                    onUpdate(updated)
                }
            )
        }
    }

}

// MARK: - Threshold Level Row

private struct ThresholdLevelRow: View {
    let title: String
    let settings: ThresholdLevelSettings
    let onCommit: () -> Void
    let onUpdate: (ThresholdLevelSettings) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text(title)
                .font(.headline)
                .frame(width: 70, alignment: .leading)

            Toggle("notification.enabled".localized(), isOn: makeEnabledBinding())
                .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            Slider(
                value: makeThresholdBinding(),
                in: 1...100,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        onCommit()
                    }
                }
            )
            .disabled(!settings.isEnabled)
            .accessibilityValue(Text("\(settings.thresholdPercent)%"))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(settings.thresholdPercent)%")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func makeEnabledBinding() -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                var updated = settings
                updated.isEnabled = newValue
                onUpdate(updated)
                onCommit()
            }
        )
    }

    private func makeThresholdBinding() -> Binding<Double> {
        Binding(
            get: { Double(clampThreshold(settings.thresholdPercent)) },
            set: { newValue in
                var updated = settings
                updated.thresholdPercent = clampThreshold(Int(newValue.rounded()))
                onUpdate(updated)
            }
        )
    }

    private func clampThreshold(_ value: Int) -> Int {
        min(max(value, 1), 100)
    }
}

// MARK: - Usage Color Settings Section


private struct UsageColorSettingsSection: View {
    @State private var donutColor: Color = UsageColorSettings.loadDonutColor()
    @State private var isDonutColorByUsage: Bool = UsageColorSettings.loadDonutUseStatus()
    @State private var statusGreenColor: Color = UsageColorSettings.loadStatusGreenColor()
    @State private var statusOrangeColor: Color = UsageColorSettings.loadStatusOrangeColor()
    @State private var statusRedColor: Color = UsageColorSettings.loadStatusRedColor()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ColorPicker("cliColors.donut".localized(), selection: $donutColor, supportsOpacity: false)
                    .disabled(isDonutColorByUsage)
                Toggle(isOn: $isDonutColorByUsage) {
                    HStack {
                        Spacer()
                        Text("cliColors.donutUseStatus".localized())
                    }
                }
                .toggleStyle(.switch)
            }

            Divider()
            ColorPicker("cliColors.green".localized(), selection: $statusGreenColor, supportsOpacity: false)
            Divider()
            ColorPicker("cliColors.orange".localized(), selection: $statusOrangeColor, supportsOpacity: false)
            Divider()
            ColorPicker("cliColors.red".localized(), selection: $statusRedColor, supportsOpacity: false)

            Divider()
            HStack {
                Spacer()
                Button("cliColors.reset".localized()) {
                    resetUsageColors()
                }
            }

        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
        .onAppear {
            reloadUsageColorSettings()
        }
        .onChange(of: donutColor) { _, _ in
            UsageColorSettings.saveDonutColor(donutColor)
            reloadUsageTimelines()
        }
        .onChange(of: isDonutColorByUsage) { _, _ in
            UsageColorSettings.saveDonutUseStatus(isDonutColorByUsage)
            reloadUsageTimelines()
        }
        .onChange(of: statusGreenColor) { _, _ in
            UsageColorSettings.saveStatusGreenColor(statusGreenColor)
            reloadUsageTimelines()
        }
        .onChange(of: statusOrangeColor) { _, _ in
            UsageColorSettings.saveStatusOrangeColor(statusOrangeColor)
            reloadUsageTimelines()
        }
        .onChange(of: statusRedColor) { _, _ in
            UsageColorSettings.saveStatusRedColor(statusRedColor)
            reloadUsageTimelines()
        }
    }

    private func reloadUsageColorSettings() {
        donutColor = UsageColorSettings.loadDonutColor()
        isDonutColorByUsage = UsageColorSettings.loadDonutUseStatus()
        statusGreenColor = UsageColorSettings.loadStatusGreenColor()
        statusOrangeColor = UsageColorSettings.loadStatusOrangeColor()
        statusRedColor = UsageColorSettings.loadStatusRedColor()
    }

    private func resetUsageColors() {
        UsageColorSettings.resetUsageStatusColors()
        reloadUsageColorSettings()
        reloadUsageTimelines()
    }

    private func reloadUsageTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Preview

#Preview {
    ThresholdSettingsView(manager: .shared)
}
