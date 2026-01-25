// MARK: - PacemakerSettingsView.swift
// Settings UI for pacemaker display, thresholds, and colors.

import SwiftUI
import WidgetKit

@MainActor
struct PacemakerSettingsView: View {
    @AppStorage(UserDefaultsKeys.menuBarShowPacemakerValue)
    private var showPacemakerValue: Bool = true

    var body: some View {
        SettingsScrollContainer {
            headerView

            Form {
                SettingsFormSection {
                    Toggle("menu.showPacemakerValue".localized(), isOn: $showPacemakerValue)
                        .toggleStyle(.checkbox)
                }

                SettingsFormSection(title: "notification.pacemakerThresholds".localized()) {
                    PacemakerThresholdSection()
                }

                SettingsFormSection(title: "cliColors.pacemaker".localized()) {
                    PacemakerColorSettingsSection()
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private var headerView: some View {
        SettingsHeaderView(
            titleText: "tab.pacemaker".localized(),
            descriptionText: "pacemaker.description".localized()
        )
    }
}

private struct PacemakerThresholdSection: View {
    @State private var warningDelta: Double = PacemakerThresholdSettings.loadWarningDelta()
    @State private var dangerDelta: Double = PacemakerThresholdSettings.loadDangerDelta()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("notification.pacemakerThresholds.description".localized())
                .font(.caption)
                .foregroundColor(.secondary)

            PacemakerThresholdRow(
                title: "notification.pacemakerThresholds.warning".localized(),
                value: $warningDelta,
                range: 0...50,
                color: .orange
            )

            Divider()

            PacemakerThresholdRow(
                title: "notification.pacemakerThresholds.danger".localized(),
                value: $dangerDelta,
                range: 1...50,
                color: .red
            )

            Divider()
            HStack {
                Spacer()
                Button("cliColors.reset".localized()) {
                    warningDelta = PacemakerThresholdSettings.defaultWarningDelta
                    dangerDelta = PacemakerThresholdSettings.defaultDangerDelta
                    PacemakerThresholdSettings.resetToDefaults()
                    reloadUsageTimelines()
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
        .onChange(of: warningDelta) { _, newValue in
            if newValue >= dangerDelta {
                dangerDelta = min(newValue + 1, 50)
            }
            PacemakerThresholdSettings.saveWarningDelta(newValue)
            reloadUsageTimelines()
        }
        .onChange(of: dangerDelta) { _, newValue in
            if newValue <= warningDelta {
                warningDelta = max(newValue - 1, 0)
            }
            PacemakerThresholdSettings.saveDangerDelta(newValue)
            reloadUsageTimelines()
        }
    }

    private func reloadUsageTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct PacemakerThresholdRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text(title)
                .font(.headline)
                .frame(width: 70, alignment: .leading)

            Spacer(minLength: 0)

            Slider(value: $value, in: range, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue(Text("+\(Int(value))%"))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("+\(Int(value))%")
                .foregroundColor(color)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
    }
}

private struct PacemakerColorSettingsSection: View {
    @State private var pacemakerRingColor: Color = UsageColorSettings.loadPacemakerRingColor()
    @State private var pacemakerTextColor: Color = UsageColorSettings.loadPacemakerTextColor()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ColorPicker("cliColors.pacemakerRing".localized(), selection: $pacemakerRingColor, supportsOpacity: true)
            Divider()
            ColorPicker("cliColors.pacemakerText".localized(), selection: $pacemakerTextColor, supportsOpacity: true)
            Divider()
            HStack {
                Spacer()
                Button("cliColors.reset".localized()) {
                    resetPacemakerColors()
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(8)
        .onAppear {
            reloadPacemakerColors()
        }
        .onChange(of: pacemakerRingColor) { _, _ in
            UsageColorSettings.savePacemakerRingColor(pacemakerRingColor)
            reloadUsageTimelines()
        }
        .onChange(of: pacemakerTextColor) { _, _ in
            UsageColorSettings.savePacemakerTextColor(pacemakerTextColor)
            reloadUsageTimelines()
        }
    }

    private func reloadPacemakerColors() {
        pacemakerRingColor = UsageColorSettings.loadPacemakerRingColor()
        pacemakerTextColor = UsageColorSettings.loadPacemakerTextColor()
    }

    private func resetPacemakerColors() {
        UsageColorSettings.resetPacemakerColors()
        reloadPacemakerColors()
        reloadUsageTimelines()
    }

    private func reloadUsageTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
