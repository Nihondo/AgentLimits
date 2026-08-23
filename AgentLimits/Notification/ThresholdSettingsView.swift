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
    @ObservedObject private var customServiceStore: CustomUsageServiceStore
    @State private var selectedServiceKey: UsageServiceKey = .builtIn(.chatgptCodex)

    init(manager: ThresholdNotificationManager) {
        self.manager = manager
        _customServiceStore = ObservedObject(wrappedValue: .shared)
    }

    var body: some View {
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

            if selectedWindowKinds.isEmpty {
                SettingsFormSection {
                    Text("customUsage.notification.runFirst".localized())
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(selectedWindowKinds, id: \.self) { windowKind in
                    SettingsFormSection(title: title(for: windowKind)) {
                    thresholdSection(
                            settings: manager.getSettings(
                                for: selectedServiceKey,
                                windowKind: windowKind
                            ),
                            windowKind: windowKind
                        )
                    }
                }
            }

            if !selectedWindowKinds.isEmpty {
                SettingsFormSection {
                    Button("notification.resetDefaults".localized()) {
                        manager.resetSettings(
                            for: selectedServiceKey,
                            windowKinds: selectedWindowKinds
                        )
                        reloadUsageWidgets()
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
        Picker("", selection: $selectedServiceKey) {
            ForEach(serviceOptions) { option in
                Text(option.displayName).tag(option.serviceKey)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260)
        .labelsHidden()
        .accessibilityLabel(Text("notification.provider".localized()))
    }

    private var serviceOptions: [NotificationServiceOption] {
        let builtIn = UsageProvider.allCases.map {
            NotificationServiceOption(serviceKey: .builtIn($0), displayName: $0.displayName)
        }
        let custom = customServiceStore.services.map {
            NotificationServiceOption(serviceKey: .custom($0.providerID), displayName: $0.displayName)
        }
        return builtIn + custom
    }

    private var selectedWindowKinds: [SemanticUsageWindowKind] {
        if let provider = selectedServiceKey.builtInProvider {
            return provider == .githubCopilot ? [.oneMonth] : [.fiveHours, .oneWeek]
        }
        guard let providerID = selectedServiceKey.customProviderID,
              let snapshot = CustomUsageSnapshotStore.shared.loadSnapshot(providerID: providerID) else {
            return manager.serviceSettings[selectedServiceKey]?.windows.keys.sorted {
                $0.displayOrder < $1.displayOrder
            } ?? []
        }
        return snapshot.windows.map(\.kind).sorted { $0.displayOrder < $1.displayOrder }
    }

    private func title(for kind: SemanticUsageWindowKind) -> String {
        switch kind {
        case .fiveHours: return "notification.primaryWindow".localized()
        case .oneWeek: return "notification.secondaryWindow".localized()
        case .oneMonth: return "notification.monthlyWindow".localized()
        }
    }

    // MARK: - Threshold Section

    private func thresholdSection(
        settings: WindowThresholdSettings,
        windowKind: SemanticUsageWindowKind
    ) -> some View {
        WindowThresholdView(
            settings: settings,
            onCommit: reloadUsageWidgets,
            onUpdate: { newWindowSettings in
                manager.updateSettings(
                    newWindowSettings,
                    for: selectedServiceKey,
                    windowKind: windowKind
                )
            }
        )
    }

    private func reloadUsageWidgets() {
        if let provider = selectedServiceKey.builtInProvider {
            WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
        } else {
            WidgetCenter.shared.reloadTimelines(ofKind: CustomUsageViewModel.widgetKind)
        }
    }
}

private struct NotificationServiceOption: Identifiable {
    let serviceKey: UsageServiceKey
    let displayName: String

    var id: UsageServiceKey { serviceKey }
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
            ColorPicker("cliColors.donut".localized(), selection: $donutColor, supportsOpacity: false)
                .disabled(isDonutColorByUsage)
            Toggle("cliColors.donutUseStatus".localized(), isOn: $isDonutColorByUsage)
                .toggleStyle(.switch)
            ColorPicker("cliColors.green".localized(), selection: $statusGreenColor, supportsOpacity: false)
            ColorPicker("cliColors.orange".localized(), selection: $statusOrangeColor, supportsOpacity: false)
            ColorPicker("cliColors.red".localized(), selection: $statusRedColor, supportsOpacity: false)
            Button("cliColors.reset".localized()) {
                resetUsageColors()
            }
        }
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
