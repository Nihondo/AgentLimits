// MARK: - CustomUsageSettingsView.swift
// Picker-based single-pane settings UI for script-backed custom usage services,
// matching the Usage/ccusage/Wake Up/Notification tabs' convention.

import AppKit
import SwiftUI
import WidgetKit

/// カスタム使用量サービスを追加・編集・削除する設定画面です。
@MainActor
struct CustomUsageSettingsView: View {
    @ObservedObject private var viewModel: CustomUsageViewModel
    @ObservedObject private var serviceStore: CustomUsageServiceStore
    @State private var selectedProviderID: String?
    @State private var isShowingAddSheet = false
    @State private var isShowingDeleteConfirmation = false

    init(viewModel: CustomUsageViewModel) {
        self.viewModel = viewModel
        _serviceStore = ObservedObject(wrappedValue: viewModel.serviceStore)
    }

    var body: some View {
        Form {
            SettingsFormSection {
                LabeledContent("notification.provider".localized()) {
                    HStack {
                        servicePicker
                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("customUsage.add".localized())

                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedProviderID == nil)
                        .accessibilityLabel("customUsage.delete.action".localized())
                    }
                }
            }

            if let providerID = selectedProviderID,
               let service = serviceStore.service(providerID: providerID) {
                serviceFormSections(service)
            } else {
                Section {
                    ContentUnavailableView(
                        "customUsage.empty.title".localized(),
                        systemImage: "terminal",
                        description: Text("customUsage.empty.message".localized())
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectPreferredServiceIfAvailable()
            selectFirstServiceIfNeeded()
        }
        .onChange(of: serviceStore.services) { _, _ in selectFirstServiceIfNeeded() }
        .onChange(of: selectedProviderID) { _, providerID in
            if let providerID {
                UserDefaults.standard.set(providerID, forKey: "selected_custom_usage_provider")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            selectPreferredServiceIfAvailable()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddCustomUsageServiceView { service in
                try serviceStore.addService(service)
                ProviderOrderStore.addService(.custom(service.providerID))
                selectedProviderID = service.providerID
                UserDefaults.standard.set(service.providerID, forKey: "selected_custom_usage_provider")
                WidgetCenter.shared.reloadTimelines(ofKind: CustomUsageViewModel.widgetKind)
            }
        }
        .confirmationDialog(
            "customUsage.delete.confirmTitle".localized(),
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("customUsage.delete.action".localized(), role: .destructive) {
                guard let providerID = selectedProviderID else { return }
                viewModel.deleteService(providerID: providerID)
                selectedProviderID = nil
                selectFirstServiceIfNeeded()
            }
            Button("content.clearDataCancel".localized(), role: .cancel) {}
        }
    }

    // MARK: - Service Picker

    private var servicePicker: some View {
        Picker("", selection: $selectedProviderID) {
            ForEach(serviceStore.services) { service in
                Text("\(service.providerID) - \(service.displayName)")
                    .tag(Optional(service.providerID))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 260)
        .labelsHidden()
    }

    @ViewBuilder
    private func serviceFormSections(_ service: CustomUsageService) -> some View {
        SettingsFormSection(title: "customUsage.identity".localized()) {
            LabeledContent("customUsage.displayName".localized()) {
                TextField("", text: serviceBinding(service, keyPath: \.displayName))
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("customUsage.providerID".localized()) {
                Text(service.providerID)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent("customUsage.website".localized()) {
                TextField("", text: serviceBinding(service, keyPath: \.websiteURLString), prompt: Text("https://"))
                    .textFieldStyle(.roundedBorder)
            }
        }

        SettingsFormSection(
            title: "customUsage.script".localized(),
            footerText: "customUsage.refreshIntervalHint".localized()
        ) {
            LabeledContent("customUsage.scriptPath".localized()) {
                HStack {
                    Text(service.scriptPath)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button("customUsage.chooseScript".localized()) {
                        if let path = chooseExecutableScript() {
                            var updated = service
                            updated.scriptPath = path
                            serviceStore.updateService(updated)
                        }
                    }
                }
            }
            Toggle(
                "customUsage.autoRefresh".localized(),
                isOn: serviceBinding(service, keyPath: \.isAutoRefreshEnabled)
            )
            Toggle(
                "settings.showInMenuBar".localized(),
                isOn: serviceBinding(service, keyPath: \.isMenuBarEnabled)
            )
            Toggle(
                "settings.showMenuDashboard".localized(),
                isOn: serviceBinding(service, keyPath: \.isDashboardEnabled)
            )
        }

        SettingsFormSection(title: "customUsage.status".localized()) {
            statusView(providerID: service.providerID)
            Button("customUsage.testNow".localized()) {
                Task { await viewModel.refresh(providerID: service.providerID) }
            }
            .disabled(viewModel.runningProviderIDs.contains(service.providerID))
            .settingsButtonStyle(.primary)
        }

        SettingsFormSection(footerText: "customUsage.schemaHelp".localized()) {
            Text("customUsage.snapshotFile".localized() + " usage_snapshot_custom_\(service.providerID).json")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func statusView(providerID: String) -> some View {
        let status = serviceStore.runStatuses[providerID] ?? .initial
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            if viewModel.runningProviderIDs.contains(providerID) {
                ProgressView("customUsage.running".localized())
                    .controlSize(.small)
            }
            LabeledContent("customUsage.lastAttempt".localized()) {
                dateText(status.lastAttemptAt)
            }
            LabeledContent("customUsage.lastSuccess".localized()) {
                dateText(status.lastSuccessAt ?? viewModel.snapshots[providerID]?.fetchedAt)
            }
            if let error = status.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func dateText(_ date: Date?) -> Text {
        guard let date else { return Text("-") }
        return Text(Self.timeFormatter.string(from: date))
    }

    private func serviceBinding<Value>(
        _ service: CustomUsageService,
        keyPath: WritableKeyPath<CustomUsageService, Value>
    ) -> Binding<Value> {
        Binding(
            get: { serviceStore.service(providerID: service.providerID)?[keyPath: keyPath] ?? service[keyPath: keyPath] },
            set: { value in
                guard var updated = serviceStore.service(providerID: service.providerID) else { return }
                updated[keyPath: keyPath] = value
                serviceStore.updateService(updated)
                WidgetCenter.shared.reloadTimelines(ofKind: CustomUsageViewModel.widgetKind)
            }
        )
    }

    private func selectFirstServiceIfNeeded() {
        if let selectedProviderID,
           serviceStore.service(providerID: selectedProviderID) != nil {
            return
        }
        selectedProviderID = serviceStore.services.first?.providerID
    }

    private func selectPreferredServiceIfAvailable() {
        guard let providerID = UserDefaults.standard.string(forKey: "selected_custom_usage_provider"),
              serviceStore.service(providerID: providerID) != nil else { return }
        selectedProviderID = providerID
    }
}

/// 新規カスタムサービスをProvider IDのみで作成するシートです。
/// 表示名・スクリプト・Webサイト・トグルは、追加後に開く詳細ペインで編集します。
private struct AddCustomUsageServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var providerID = ""
    @State private var validationMessage: String?
    let onSave: (CustomUsageService) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            Text("customUsage.add".localized())
                .font(.title2.bold())
            Form {
                LabeledContent("customUsage.providerID".localized()) {
                    TextField("", text: $providerID, prompt: Text("cursor"))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Text("customUsage.add.providerIDHint".localized())
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("content.clearDataCancel".localized()) { dismiss() }
                Button("customUsage.add".localized()) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func save() {
        let normalizedID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CustomUsageSnapshotValidator.isProviderIDValid(normalizedID) else {
            validationMessage = CustomUsageSnapshotValidationError.invalidProviderID.localizedDescription
            return
        }
        do {
            try onSave(CustomUsageService(
                providerID: normalizedID,
                displayName: normalizedID,
                scriptPath: "",
                websiteURLString: "",
                isAutoRefreshEnabled: true,
                isMenuBarEnabled: false,
                isDashboardEnabled: true
            ))
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

@MainActor
private func chooseExecutableScript() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.prompt = "customUsage.chooseScript".localized()
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let path = url.standardizedFileURL.path
    guard isRegularExecutableFile(atPath: path) else { return nil }
    return path
}

private func isRegularExecutableFile(atPath path: String) -> Bool {
    guard !path.isEmpty else { return false }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        && FileManager.default.isExecutableFile(atPath: url.path)
}
