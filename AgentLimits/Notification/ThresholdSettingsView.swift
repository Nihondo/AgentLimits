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
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()

            if !manager.isNotificationAuthorized {
                authorizationSection
                Divider()
            }

            providerPicker
            thresholdSection

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("notification.title".localized())
                .font(.title2)
                .bold()
            Text("notification.description".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Authorization Section

    private var authorizationSection: some View {
        HStack {
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
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("notification.provider".localized(), selection: $selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    // MARK: - Threshold Section

    private var thresholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let settings = manager.getSettings(for: selectedProvider)

            WindowThresholdView(
                title: "notification.primaryWindow".localized(),
                settings: settings.primaryWindow,
                onCommit: {
                    reloadUsageWidgets(for: selectedProvider)
                },
                onUpdate: { newWindowSettings in
                    var updated = settings
                    updated.primaryWindow = newWindowSettings
                    manager.updateSettings(updated)
                }
            )

            WindowThresholdView(
                title: "notification.secondaryWindow".localized(),
                settings: settings.secondaryWindow,
                onCommit: {
                    reloadUsageWidgets(for: selectedProvider)
                },
                onUpdate: { newWindowSettings in
                    var updated = settings
                    updated.secondaryWindow = newWindowSettings
                    manager.updateSettings(updated)
                }
            )

            HStack {
                Spacer()
                Button("notification.resetDefaults".localized()) {
                    manager.resetSettings(for: selectedProvider)
                    reloadUsageWidgets(for: selectedProvider)
                }
            }
        }
    }

    private func reloadUsageWidgets(for provider: UsageProvider) {
        WidgetCenter.shared.reloadTimelines(ofKind: provider.widgetKind)
    }
}

// MARK: - Window Threshold View

/// Configuration view for a single window's threshold settings
private struct WindowThresholdView: View {
    let title: String
    let settings: WindowThresholdSettings
    let onCommit: () -> Void
    let onUpdate: (WindowThresholdSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

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
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
    }

}

// MARK: - Threshold Level Row

private struct ThresholdLevelRow: View {
    let title: String
    let settings: ThresholdLevelSettings
    let onCommit: () -> Void
    let onUpdate: (ThresholdLevelSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .frame(width: 70, alignment: .leading)

                Toggle("notification.enabled".localized(), isOn: makeEnabledBinding())
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 12) {
                Slider(
                    value: makeThresholdBinding(),
                    in: 1...100,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            onCommit()
                        }
                    }
                )
                .disabled(!settings.isEnabled)
                .accessibilityValue(Text("\(settings.thresholdPercent)%"))

                Text("\(settings.thresholdPercent)%")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
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

// MARK: - Preview

#Preview {
    ThresholdSettingsView(manager: .shared)
}
