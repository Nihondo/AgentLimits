// MARK: - ThresholdSettingsView.swift
// Settings UI for configuring usage threshold notifications.
// Allows users to set per-provider, per-window notification thresholds.

import SwiftUI

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
                onUpdate: { newWindowSettings in
                    var updated = settings
                    updated.primaryWindow = newWindowSettings
                    manager.updateSettings(updated)
                }
            )

            WindowThresholdView(
                title: "notification.secondaryWindow".localized(),
                settings: settings.secondaryWindow,
                onUpdate: { newWindowSettings in
                    var updated = settings
                    updated.secondaryWindow = newWindowSettings
                    manager.updateSettings(updated)
                }
            )
        }
    }
}

// MARK: - Window Threshold View

/// Configuration view for a single window's threshold settings
private struct WindowThresholdView: View {
    let title: String
    let settings: WindowThresholdSettings
    let onUpdate: (WindowThresholdSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Toggle("notification.enabled".localized(), isOn: enabledBinding)

            if settings.isEnabled {
                HStack {
                    Text("notification.threshold".localized())
                    Stepper(
                        "\(settings.thresholdPercent)%",
                        value: thresholdBinding,
                        in: 1...100,
                        step: 1
                    )
                    .monospacedDigit()
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
                // Propagate enabled toggle to the settings store.
                var updated = settings
                updated.isEnabled = newValue
                onUpdate(updated)
            }
        )
    }

    private var thresholdBinding: Binding<Int> {
        Binding(
            get: { settings.thresholdPercent },
            set: { newValue in
                // Persist updated threshold percent.
                var updated = settings
                updated.thresholdPercent = newValue
                onUpdate(updated)
            }
        )
    }
}

// MARK: - Preview

#Preview {
    ThresholdSettingsView(manager: .shared)
}
