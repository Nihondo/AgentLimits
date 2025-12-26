// MARK: - WakeUpSettingsView.swift
// Settings UI for configuring wake-up schedules via LaunchAgent.
// Allows users to select hours for CLI execution and manage login items.

import SwiftUI

// MARK: - Wake Up Settings View

/// Settings view for configuring wake-up schedules
@MainActor
struct WakeUpSettingsView: View {
    @ObservedObject private var scheduler: WakeUpScheduler
    @State private var selectedProvider: UsageProvider = .chatgptCodex

    init(scheduler: WakeUpScheduler) {
        self.scheduler = scheduler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            Divider()

            providerPicker
            scheduleSection
            Divider()
            statusSection

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("wakeUp.title".localized())
                .font(.title2)
                .bold()
            Text("wakeUp.description".localized())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("wakeUp.provider".localized(), selection: $selectedProvider) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        Group {
            if let schedule = scheduler.schedules[selectedProvider] {
                ProviderScheduleView(
                    schedule: schedule,
                    isTestRunning: scheduler.isTestRunning[selectedProvider] ?? false,
                    onEnabledChange: { newEnabled in
                        var updated = schedule
                        updated.isEnabled = newEnabled
                        scheduler.updateSchedule(updated)
                    },
                    onUpdate: { updatedSchedule in
                        // Use current isEnabled to avoid race condition with TextField
                        guard let current = scheduler.schedules[selectedProvider] else { return }
                        var merged = updatedSchedule
                        merged.isEnabled = current.isEnabled
                        scheduler.updateSchedule(merged)
                    },
                    onTestWakeUp: {
                        Task { await scheduler.triggerWakeUp(for: selectedProvider) }
                    }
                )
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("wakeUp.status".localized())
                .font(.headline)

            ForEach(UsageProvider.allCases) { provider in
                providerStatusRow(for: provider)
            }

            lastResultView
        }
    }

    private func providerStatusRow(for provider: UsageProvider) -> some View {
        HStack {
            Circle()
                .fill(statusColor(for: provider))
                .frame(width: 8, height: 8)
            Text(provider.displayName)
                .font(.body)
            Spacer()

            if let schedule = scheduler.schedules[provider],
               schedule.isEnabled,
               !schedule.enabledHours.isEmpty {
                Text(scheduleText(for: schedule))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("wakeUp.notScheduled".localized())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastResultView: some View {
        Group {
            if let result = scheduler.lastWakeUpResults[selectedProvider] {
                HStack {
                    Text("wakeUp.lastResult".localized())
                        .font(.footnote)
                    switch result {
                    case .success:
                        Label("wakeUp.success".localized(), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.footnote)
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.footnote)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(for provider: UsageProvider) -> Color {
        guard let schedule = scheduler.schedules[provider],
              schedule.isEnabled,
              !schedule.enabledHours.isEmpty else {
            return .gray
        }
        return scheduler.isLaunchAgentInstalled(for: provider) ? .green : .orange
    }

    private func scheduleText(for schedule: WakeUpSchedule) -> String {
        let hours = schedule.enabledHours.sorted()
        if hours.count <= 3 {
            return hours.map { "\($0):00" }.joined(separator: ", ")
        } else {
            return "\(hours.count) " + "wakeUp.hoursSelected".localized()
        }
    }
}

// MARK: - Provider Schedule View

/// Schedule configuration for a single provider
private struct ProviderScheduleView: View {
    let schedule: WakeUpSchedule
    let isTestRunning: Bool
    let onEnabledChange: (Bool) -> Void
    let onUpdate: (WakeUpSchedule) -> Void
    let onTestWakeUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("wakeUp.enabled".localized(), isOn: enabledBinding)

            if schedule.isEnabled {
                Text("wakeUp.selectHours".localized())
                    .font(.body)

                HourGridView(
                    selectedHours: schedule.enabledHours,
                    onToggle: { hour in
                        var newHours = schedule.enabledHours
                        if newHours.contains(hour) {
                            newHours.remove(hour)
                        } else {
                            newHours.insert(hour)
                        }
                        onUpdate(WakeUpSchedule(
                            provider: schedule.provider,
                            enabledHours: newHours,
                            isEnabled: schedule.isEnabled,
                            additionalArgs: schedule.additionalArgs
                        ))
                    }
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("wakeUp.command".localized())
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(schedule.cliCommand)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("wakeUp.additionalArgs".localized())
                        .font(.body)
                        .foregroundStyle(.secondary)
                    TextField("wakeUp.additionalArgsPlaceholder".localized(), text: additionalArgsBinding)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("wakeUp.selectedHours".localized())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(selectedHoursText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("wakeUp.testNow".localized()) {
                        onTestWakeUp()
                    }
                    .disabled(isTestRunning)

                    if isTestRunning {
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
            get: { schedule.isEnabled },
            set: { newValue in
                onEnabledChange(newValue)
            }
        )
    }

    private var additionalArgsBinding: Binding<String> {
        Binding(
            get: { schedule.additionalArgs },
            set: { newValue in
                onUpdate(WakeUpSchedule(
                    provider: schedule.provider,
                    enabledHours: schedule.enabledHours,
                    isEnabled: schedule.isEnabled,
                    additionalArgs: newValue
                ))
            }
        )
    }

    private var selectedHoursText: String {
        if schedule.enabledHours.isEmpty {
            return "wakeUp.noHoursSelected".localized()
        }
        return schedule.enabledHours.sorted().map { "\($0):00" }.joined(separator: ", ")
    }
}

// MARK: - Hour Grid View

/// Grid for selecting hours (0-23)
private struct HourGridView: View {
    let selectedHours: Set<Int>
    let onToggle: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<24, id: \.self) { hour in
                Button {
                    onToggle(hour)
                } label: {
                    Text(String(format: "%02d", hour))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selectedHours.contains(hour)
                                ? Color.accentColor
                                : Color.secondary.opacity(0.2)
                        )
                        .foregroundColor(
                            selectedHours.contains(hour) ? .white : .primary
                        )
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WakeUpSettingsView(scheduler: .shared)
}
